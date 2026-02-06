"""
    StreamingSink

Direct Arrow storage with WebSocket streaming and frame collection.

Implements proper columnar Arrow storage (matching ExperimentTool format) while adding:
1. SimulationFrame collection for in-memory access
2. WebSocket broadcasting as frames are collected
3. Direct file I/O (no dependency on ExperimentTool.artifact system)

Storage format matches ExperimentTool:
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
    is::Vector{Int64} = Int64[]           # episode indices
    ts::Vector{Float64} = Float64[]       # time points
    names::Vector{Symbol} = Symbol[]      # event names
    values::Vector{Int64} = Int64[]       # event values
end

"""
    StreamingSimulationSink

Direct Arrow sink with WebSocket frame streaming coupled to flushes.

Collects simulation events into columnar format for Arrow storage. When events
are flushed to disk, they are converted to frames and streamed via WebSocket
in batches.

# Fields
- `location::String`: Directory path for storing Arrow files
- `i::Int`: Episode counter for tracking execution paths
- `index::Vector`: Metadata for each execution segment
- `threshold::Int`: Event buffer threshold before flush to disk
- `channels::Dict{String, Channel}`: Accumulated events by channel
- `ws_client::Union{HTTP.WebSocket, Nothing}`: WebSocket client for streaming
- `i_to_path::Dict{Int, String}`: Episode index to path mapping for frame reconstruction
"""
@kwdef mutable struct StreamingSimulationSink
    location::String
    i::Int = 0
    index::Vector = []
    threshold::Int = 200000
    channels::Dict{String, Channel} = Dict{String, Channel}()
    ws_client::Union{HTTP.WebSocket, Nothing} = nothing
    i_to_path::Dict{Int, String} = Dict{Int, String}()
end

# ============================================================================
# Core Sink Callback
# ============================================================================

"""
    (sink::StreamingSimulationSink)(into, state; path, primitive!, from, seed, _...)

Implement Sink interface (callable struct).

Called for each state transition during schedule execution. Accumulates events
into columnar format and broadcasts to WebSocket clients.

Matches ExperimentTool.Sink interface for compatibility.
"""
function (sink::StreamingSimulationSink)(into, state; path, primitive!, from, seed, _...)
    sink.i += 1

    to = Models.t(state)
    model = primitive!.path
    label = get(primitive!.bindings, :label, "")

    # Record index metadata
    if into === nothing
        @debug "[StreamingSink] Recording index entry (no output)" i=sink.i path=path from=from to=to model=model label=label
        push!(
            sink.index,
            (; sink.i, path, from, to, model, label, count = 0, into = "", seed)
        )
        sink.i_to_path[sink.i] = path
        return
    end

    # Accumulate events from this state
    channel = get!(Channel, sink.channels, into)
    count = 0

    Models.each_event(state) do t::Float64, name::Symbol, value::Int64
        # Flush buffer if threshold reached
        if length(channel.values) ≥ sink.threshold
            @debug "[StreamingSink] Flushing channel (threshold reached)" into=into buffered=length(channel.values)
            _flush_channel!(sink, into)
            channel = sink.channels[into] = Channel()
        end

        push!(channel.is, sink.i)
        push!(channel.ts, t)
        push!(channel.names, name)
        push!(channel.values, value)
        count += 1
    end

    @debug "[StreamingSink] Recording execution segment" i=sink.i into=into from=from to=to count=count buffered=length(channel.values)

    # Record execution segment metadata
    push!(
        sink.index,
        (; sink.i, path, from, to, model, label, count, into, seed)
    )
    sink.i_to_path[sink.i] = path
end

# ============================================================================
# Flushing to Disk
# ============================================================================

"""
    flush!(sink::StreamingSimulationSink)

Flush all accumulated events to Arrow files and stream frames via WebSocket.

For each channel:
1. Write events_*.arrow to disk
2. Convert events to frames
3. Stream frames in batches via WebSocket (threshold-sized batches)
4. Write index.arrow with metadata
"""
function flush!(sink::StreamingSimulationSink)
    sink.i > 0 || return

    @info "Flushing streaming sink"

    # Flush all channel data and stream frames
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
        @debug "Wrote Arrow index file" index_file
    end
end

"""
    _flush_channel!(sink::StreamingSimulationSink, into::String)

Internal: flush a single channel's buffered events to disk and stream frames.

1. Writes events_*.arrow file
2. Converts events to frames
3. Streams frames via WebSocket
"""
function _flush_channel!(sink::StreamingSimulationSink, into::String)
    channel = pop!(sink.channels, into)
    filename = joinpath(sink.location, "events$into.stream.arrow")

    @info "[StreamingSink] Flushing channel to disk" into=into filename=filename events=length(channel.ts)

    events = (;
        i = channel.is,
        t = channel.ts,
        name = channel.names,
        value = channel.values,
    )

    if isfile(filename)
        @debug "[StreamingSink] Appending to existing Arrow file" filename
        Arrow.append(filename, events)
    else
        @debug "[StreamingSink] Creating new Arrow file" filename
        Arrow.write(filename, events, file = false)
    end

    @info "[StreamingSink] Wrote Arrow events file" filename event_count=length(events.t)

    # Convert events to frames and stream
    _convert_and_stream_frames(sink, events)
end

"""
    _convert_and_stream_frames(sink::StreamingSimulationSink, events::NamedTuple)

Internal: convert events to frames and stream via WebSocket.

Groups events by (episode_i, time), reconstructs frames, and sends
via WebSocket if client is connected.
"""
function _convert_and_stream_frames(sink::StreamingSimulationSink, events::NamedTuple)
    isnothing(sink.ws_client) && (@debug "[StreamingSink] No WebSocket client; skipping frame conversion"; return)

    # Group events by (episode_i, time)
    events_by_state = Dict{Tuple{Int, Float64}, Vector}()

    for idx in eachindex(events.i)
        i = events.i[idx]
        t = events.t[idx]
        name = events.name[idx]
        value = events.value[idx]

        key = (i, t)
        if !haskey(events_by_state, key)
            events_by_state[key] = []
        end
        push!(events_by_state[key], (i=i, t=t, name=name, value=value))
    end

    # Reconstruct frames
    frames = SimulationFrame[]
    for ((episode_i, t), state_events) in events_by_state
        path = get(sink.i_to_path, episode_i, string(episode_i))
        counts = Dict{String, Int}()
        for event in state_events
            counts[String(event.name)] = event.value
        end
        push!(frames, SimulationFrame(path=path, t=t, counts=counts))
    end

    @info "[StreamingSink] Converted to frames" frame_count=length(frames) unique_states=length(events_by_state)

    # Stream all frames in one message
    _broadcast_frames(sink, frames)
end

# ============================================================================
# WebSocket Broadcasting
# ============================================================================

"""
    _broadcast_frames(sink::StreamingSimulationSink, frames::Vector{SimulationFrame})

Internal: send frames to WebSocket client as a single message.
"""
function _broadcast_frames(sink::StreamingSimulationSink, frames::Vector{SimulationFrame})
    if isnothing(sink.ws_client)
        @debug "[StreamingSink] No WebSocket client for broadcasting"
        return
    end

    if isempty(frames)
        @debug "[StreamingSink] No frames to broadcast"
        return
    end

    @info "[StreamingSink] Broadcasting frames via WebSocket" frame_count=length(frames)

    message = Dict(
        "type" => "frames",
        "data" => frames
    )

    try
        send(sink.ws_client, JSON.json(message))
        @debug "[StreamingSink] Frames sent successfully" frame_count=length(frames)
    catch e
        @error "[StreamingSink] Error sending frames" exception=string(e)
    end
end

end # module StreamingSink
