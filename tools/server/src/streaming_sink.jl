"""
    StreamingSink

Direct Arrow storage with WebSocket streaming for simulation events.

Implements columnar Arrow storage (matching ExperimentTool format) with:
1. Time-window-based progress reporting via SimulationController
2. Filtered timeseries streaming (only subscribed species)
3. Pause/resume checkpoint at each trace callback
4. Direct file I/O (no dependency on ExperimentTool.artifact system)

Storage format:
- `index.arrow`: Metadata about execution paths
- `events_*.arrow`: Event columns (i, t, name, value) for each channel
"""
module StreamingSink

using GeneRegulatorySystems
using GeneRegulatorySystems.Models
using GeneRegulatorySystems.Models.Scheduling
using HTTP
import HTTP: send
using JSON
using Logging
using Arrow
using Tables

export StreamingSimulationSink, flush!

# ============================================================================
# Types
# ============================================================================

"""
    SimulationFrame

A point in time with sparse species state changes.
"""
@kwdef struct SimulationFrame
    path::String
    t::Float64
    counts::Dict{String, Int}
end

"""
    Channel

Accumulates events for a single execution channel.
Matches ExperimentTool.Channel format for efficient Arrow columnar storage.
"""
@kwdef struct Channel
    is::Vector{Int64} = Int64[]
    ts::Vector{Float64} = Float64[]
    names::Vector{Symbol} = Symbol[]
    values::Vector{Int64} = Int64[]
end

"""
    StreamingSimulationSink

Direct Arrow sink with optional WebSocket streaming via SimulationController.

# Fields
- `location::String`: Directory for Arrow files
- `i::Int`: Episode counter
- `index::Vector`: Execution segment metadata
- `threshold::Int`: Event buffer size before flush (default 200k)
- `channels::Dict{String, Channel}`: Buffered events by channel
- `ws_client::Union{HTTP.WebSocket, Nothing}`: WebSocket for streaming
- `controller`: SimulationController for pause/progress/timeseries (duck-typed)
- `i_to_path::Dict{Int, String}`: Episode index to path mapping
- `stream_event_interval::Int`: Number of events between WS timeseries sends
- `events_since_stream::Int`: Events accumulated since last stream
- `pending_timeseries::Dict`: Accumulated timeseries for subscribed species since last stream
- `frame_count::Int`: Running count of frames for progress reporting
- `path_run_predecessor::Dict{String, Dict{Float64, Float64}}`: run_predecessor[path][to] = from for each non-instant episode (gap detection)
- `path_last_to::Dict{String, Float64}`: Last covered end-time per path (gap detection)
"""
@kwdef mutable struct StreamingSimulationSink
    location::String
    i::Int = 0
    index::Vector = []
    threshold::Int = 200000
    channels::Dict{String, Channel} = Dict{String, Channel}()
    ws_client::Union{HTTP.WebSocket, Nothing} = nothing
    controller::Any = nothing
    i_to_path::Dict{Int, String} = Dict{Int, String}()
    stream_event_interval::Int = 100000
    events_since_stream::Int = 0
    pending_timeseries::Dict{Symbol, Dict{String, Vector{Tuple{Float64, Int}}}} = Dict{Symbol, Dict{String, Vector{Tuple{Float64, Int}}}}()
    frame_count::Int = 0
    # Gap tracking: mirrors the run_predecessor approach in _load_events_as_timeseries.
    # path_run_predecessor[path][to] = from  for every non-instant (from < to) episode.
    # path_last_to[path]              = last covered `to` (updated for all episodes).
    # Together they let the gap check handle step-based schedules where snapshot episodes
    # (from == to) would otherwise stall path_last_to.
    path_run_predecessor::Dict{String, Dict{Float64, Float64}} = Dict{String, Dict{Float64, Float64}}()
    path_last_to::Dict{String, Float64} = Dict{String, Float64}()
end

# ============================================================================
# Core Sink Callback
# ============================================================================

"""
    (sink::StreamingSimulationSink)(into, state; path, primitive!, from, seed, _...)

Sink interface (callable struct). Called for each state transition.
Accumulates events, checks pause, reports progress, and streams filtered timeseries.
"""
function (sink::StreamingSimulationSink)(into, state; path, primitive!, from, seed, _...)
    # Check pause before processing
    _check_pause_if_needed(sink)

    sink.i += 1
    to = Models.t(state)
    model = primitive!.path
    label = haskey(primitive!.bindings, :label) ? primitive!.bindings[:label] : ""

    # Record index metadata (no output channel)
    if into === nothing
        @debug "[StreamingSink] Index entry (no output)" i=sink.i path=path
        push!(sink.index, (; sink.i, path, from, to, model, label, count = 0, into = "", seed))
        sink.i_to_path[sink.i] = path
        return
    end

    # Accumulate events from this state
    channel = get!(Channel, sink.channels, into)
    count = 0

    # Eagerly insert a NaN gap marker into pending_timeseries for every subscribed species
    # when the episode's bridging run interval starts after the last covered endpoint.
    # Uses the same run_predecessor logic as _load_events_as_timeseries so that step-based
    # schedules (snapshot-only episodes) are handled correctly.
    # Insertion is eager to avoid multi-species ordering bugs.
    if !isnothing(sink.controller)
        prev_end = get(sink.path_last_to, path, NaN)
        run_pred = get(sink.path_run_predecessor, path, Dict{Float64, Float64}())
        predecessor_from = get(run_pred, from, NaN)
        gap_start = isnan(predecessor_from) ? from : predecessor_from
        if !isnan(prev_end) && gap_start > prev_end + 1e-9
            gap_t = prev_end + 1e-9
            for sp in sink.controller.subscribed_species
                species_dict = get!(sink.pending_timeseries, sp) do
                    Dict{String, Vector{Tuple{Float64, Int}}}()
                end
                series = get!(species_dict, path) do; Tuple{Float64, Int}[] end
                if isempty(series) || series[end][2] != Int64(-1)
                    push!(series, (gap_t, Int64(-1)))
                end
            end
        end
    end

    Models.each_event(state) do t::Float64, name::Symbol, value::Int64
        # Flush buffer if threshold reached
        if length(channel.values) >= sink.threshold
            @debug "[StreamingSink] Flushing channel (threshold)" into=into
            _flush_channel!(sink, into)
            channel = sink.channels[into] = Channel()
        end

        push!(channel.is, sink.i)
        push!(channel.ts, t)
        push!(channel.names, name)
        push!(channel.values, value)
        count += 1
        sink.events_since_stream += 1

        _accumulate_subscribed(sink, name, path, t, value)

        # Stream inside the event loop at regular event intervals
        if sink.events_since_stream >= sink.stream_event_interval
            _check_pause_if_needed(sink)
            _stream_update(sink, t)
            sink.events_since_stream = 0
        end
    end

    sink.frame_count += 1

    # Record execution segment metadata
    push!(sink.index, (; sink.i, path, from, to, model, label, count, into, seed))
    sink.i_to_path[sink.i] = path

    # Update gap tracking (mirrors simulation.jl: run_predecessor for non-instant, last_to for all)
    if from < to
        get!(sink.path_run_predecessor, path) do; Dict{Float64, Float64}() end[to] = from
    end
    sink.path_last_to[path] = to

    # Stream at episode boundary.
    # For step-based (snapshot) schedules, each snapshot has far fewer events
    # than stream_event_interval so we stream unconditionally after every
    # snapshot episode (from == to) to give one frame per step.
    is_snapshot = from >= to - 1e-9
    if is_snapshot || sink.events_since_stream >= sink.stream_event_interval
        _stream_update(sink, to)
        sink.events_since_stream = 0
    end
end

# ============================================================================
# Pause Support
# ============================================================================

function _check_pause_if_needed(sink::StreamingSimulationSink)
    isnothing(sink.controller) && return
    ctrl = sink.controller
    ctrl.paused || return

    lock(ctrl.pause_condition) do
        while ctrl.paused
            @info "[StreamingSink] Simulation paused, blocking..."
            wait(ctrl.pause_condition)
        end
    end
end

# ============================================================================
# Subscribed Species Streaming
# ============================================================================

"""
Accumulate a data point for subscribed species into the pending buffer.
"""
function _accumulate_subscribed(sink::StreamingSimulationSink, name::Symbol, path::String, t::Float64, value::Int64)
    isnothing(sink.controller) && return
    name in sink.controller.subscribed_species || return

    species_dict = get!(sink.pending_timeseries, name) do
        Dict{String, Vector{Tuple{Float64, Int}}}()
    end
    series = get!(species_dict, path) do; Tuple{Float64, Int}[] end
    push!(series, (t, value))
end

"""
Send accumulated timeseries + progress to WS client, then clear the buffer.
"""
function _stream_update(sink::StreamingSimulationSink, current_time::Float64)
    isnothing(sink.controller) && return
    ctrl = sink.controller
    isnothing(ctrl.ws_client) && return

    # Send progress
    @info "[StreamingSink] Streaming update" current_time=current_time frame_count=sink.frame_count subscribed=length(ctrl.subscribed_species) pending=length(sink.pending_timeseries)
    _ws_send(ctrl.ws_client, Dict(
        "type" => "progress",
        "simulation_id" => ctrl.simulation_id,
        "current_time" => current_time,
        "frame_count" => sink.frame_count
    ))

    # Send timeseries if any accumulated
    if !isempty(sink.pending_timeseries)
        n_points = sum(sum(length(pts) for pts in values(pd)) for pd in values(sink.pending_timeseries))
        @info "[StreamingSink] Sending timeseries" species=length(sink.pending_timeseries) points=n_points
        _ws_send_timeseries(ctrl.ws_client, ctrl.simulation_id, sink.pending_timeseries)
        empty!(sink.pending_timeseries)
    end
end

function _ws_send(ws::HTTP.WebSocket, data::Dict)
    try
        send(ws, JSON.json(data))
    catch e
        @warn "[StreamingSink] WS send failed" exception=string(e)
    end
end

function _ws_send_timeseries(ws::HTTP.WebSocket, simulation_id::String,
                             timeseries::Dict{Symbol, Dict{String, Vector{Tuple{Float64, Int}}}})
    # Convert to JSON-friendly: { species: { path: [[t, v], ...] } }
    data = Dict{String, Dict{String, Vector{Vector{Any}}}}()
    for (species, path_data) in timeseries
        sp = String(species)
        data[sp] = Dict{String, Vector{Vector{Any}}}()
        for (path, points) in path_data
            data[sp][path] = [[t, v] for (t, v) in points]
        end
    end

    _ws_send(ws, Dict(
        "type" => "timeseries",
        "simulation_id" => simulation_id,
        "data" => data
    ))
end

# ============================================================================
# Flushing to Disk
# ============================================================================

"""
    flush!(sink)

Flush all accumulated events to Arrow files. Sends final timeseries update.
"""
function flush!(sink::StreamingSimulationSink)
    sink.i > 0 || return
    @info "[StreamingSink] Flushing all channels"

    for into in keys(sink.channels)
        _flush_channel!(sink, into)
    end

    # Write index metadata
    if !isempty(sink.index)
        index = Tables.columntable(sink.index)
        index_file = joinpath(sink.location, "index.arrow")
        Arrow.write(index_file, (;
            index.i,
            index.path,
            index.from,
            index.to,
            model = Arrow.DictEncode(index.model),
            label = Arrow.DictEncode(index.label),
            index.count,
            into = Arrow.DictEncode(index.into),
            index.seed,
        ))
        @debug "[StreamingSink] Wrote index file" index_file
    end

    # Final timeseries flush
    if !isempty(sink.pending_timeseries) && !isnothing(sink.controller)
        ctrl = sink.controller
        if !isnothing(ctrl.ws_client)
            _ws_send_timeseries(ctrl.ws_client, ctrl.simulation_id, sink.pending_timeseries)
        end
        empty!(sink.pending_timeseries)
    end
end

"""
Flush a single channel's buffered events to disk.
"""
function _flush_channel!(sink::StreamingSimulationSink, into::String)
    channel = pop!(sink.channels, into)
    filename = joinpath(sink.location, "events$into.stream.arrow")

    @info "[StreamingSink] Flushing channel" into=into events=length(channel.ts)

    events = (;
        i = channel.is,
        t = channel.ts,
        name = channel.names,
        value = channel.values,
    )

    if isfile(filename)
        Arrow.append(filename, events)
    else
        Arrow.write(filename, events, file = false)
    end
end

end # module
