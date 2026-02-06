"""
    Simulation

Module for managing simulation execution, storage, and loading.

Handles result metadata, result listing/loading, and integration with StreamingSink
for incremental Arrow storage during execution.
"""
module Simulation

using Dates
using JSON
using Arrow
import Tables

import ..StreamingSink
import ..ScheduleStorage
import GeneRegulatorySystems.Models
import GeneRegulatorySystems.Models.Scheduling
import HTTP
import HTTP: send

# Re-export SimulationFrame from StreamingSink
export SimulationFrame, SimulationData, SimulationResultMetadata, SimulationResult
export update_result_metadata, load_result_metadata, load_result, list_results, delete_result,
       get_result_path, load_timeseries_from_result, results_dir

# ============================================================================
# Types
# ============================================================================

# Re-export from StreamingSink
const SimulationFrame = StreamingSink.SimulationFrame

"""
    SimulationData

Container for simulation timeseries data.

# Fields
- `timeseries::Dict{Symbol, Dict{String, Vector{Tuple{Float64, Int}}}}`:
  Timeseries data nested by species symbol → execution path → [(time, count), ...]
  Each path's timeseries is sorted by time.
"""
@kwdef struct SimulationData
    timeseries::Dict{Symbol, Dict{String, Vector{Tuple{Float64, Int}}}} = Dict()
end

"""
    SimulationResultMetadata

Metadata for a stored simulation result without frame data.

Use this for API responses that don't load frames (e.g., listing results).
Use SimulationResult when frames are included.

# Fields
- `id::String`: Unique simulation ID (ISO 8601 timestamp)
- `created_at::DateTime`: When simulation was run
- `schedule_name::String`: Name of the schedule that was run (e.g., "repressilator")
- `status::String`: "running", "completed", or "error"
- `frame_count::Int`: Number of frames collected
- `error::Union{String, Nothing}`: Error message if status is "error"
- `path::String`: Path to stored result directory (internal use)
"""
@kwdef struct SimulationResultMetadata
    id::String
    created_at::DateTime
    schedule_name::String = ""
    schedule_spec::String = ""
    status::String
    frame_count::Int = 0
    error::Union{String, Nothing} = nothing
    path::String = ""  # Internal use, not sent to frontend
end



"""
    SimulationResult

Full simulation result with metadata and frame data.

Combines SimulationResultMetadata with frames. Use SimulationResultMetadata
when only metadata is needed (e.g., listing results).

# Fields
- All fields from SimulationResultMetadata
- `data::Union{SimulationData, Nothing}`: Collected simulation frames
"""
@kwdef struct SimulationResult
    id::String
    created_at::DateTime
    schedule_name::String = ""
    schedule_spec::String = ""
    status::String
    frame_count::Int = 0
    error::Union{String, Nothing} = nothing
    data::Union{SimulationData, Nothing} = nothing
    path::String = ""  # Internal use, not sent to frontend
end

SimulationResult(m::SimulationResultMetadata; data::Union{SimulationData, Nothing} = nothing) =
    SimulationResult(
        m.id, m.created_at, m.schedule_name, m.schedule_spec,
        m.status, m.frame_count, m.error, data, m.path
    )

# ============================================================================
# Storage Management
# ============================================================================

"""
    results_dir()

Get the results directory path, creating it if needed.

Results are stored relative to the server module directory.
"""
function results_dir()
    dir = joinpath(@__DIR__, "..", "storage", "results")
    mkpath(dir)
    return dir
end

"""
    get_result_path(simulation_id::String)

Get the directory path for a specific simulation result.
"""
function get_result_path(simulation_id::String)
    joinpath(results_dir(), simulation_id)
end

"""
    generate_simulation_id()

Generate a unique simulation ID using ISO 8601 timestamp format.

Format: YYYY-MM-DDTHH:MM:SS.sss (e.g., 2025-11-24T23:00:33.954)
"""
function generate_simulation_id()
    Dates.format(now(), "yyyy-mm-ddTHH:MM:SS.sss")
end

"""
    load_model_from_spec(schedule_spec::String)::Models.Model

Parse and construct a Model from a schedule specification string.

# Arguments
- `schedule_spec::String`: JSON schedule specification

# Returns
- `Models.Model`: Constructed model ready for execution

# Throws
- Error if JSON parsing fails or model construction fails
"""
function load_model_from_spec(schedule_spec::String)::Models.Model
    try
        spec = JSON.parse(schedule_spec, dicttype=Dict{Symbol, Any})
        model = Models.Model(
            spec;
            bindings = Dict(
                :seed => get(spec, :seed, "default"),
                :into => "",
                :channel => "",
                :defaults => Models.load_defaults(),
            ),
        )
        return model
    catch e
        error("Failed to load model from specification: $(e.msg)")
    end
end

# ============================================================================
# Result Preparation and Execution
# ============================================================================

"""
    prepare_result(schedule_name::String, schedule_spec::String)::SimulationResultMetadata

Prepare a simulation result directory with initial metadata.

Creates result directory, writes schedule snapshot, and initializes metadata.json
with status=running. Returns metadata object for immediate API response.

# Arguments
- `schedule_name::String`: Name of the schedule (for result identification)
- `schedule_spec::String`: Schedule JSON specification (written to disk)

# Returns
- `SimulationResultMetadata`: Initial metadata with status=running
"""
function prepare_result(schedule_name::String, schedule_spec::String)::SimulationResultMetadata
    result_id = generate_simulation_id()
    result_path = get_result_path(result_id)
    mkpath(result_path)

    # Write schedule snapshot
    open(joinpath(result_path, "schedule.json"), "w") do f
        write(f, schedule_spec)
    end

    # Write initial metadata
    metadata = Dict(
        "id" => result_id,
        "schedule_name" => schedule_name,
        "status" => "running",
        "frame_count" => 0
    )

    open(joinpath(result_path, "metadata.json"), "w") do f
        JSON.print(f, metadata, 2)
    end

    created_at = try
        Dates.DateTime(result_id, "yyyy-mm-ddTHH:MM:SS.sss")
    catch
        now()
    end

    return SimulationResultMetadata(
        id = result_id,
        created_at = created_at,
        schedule_name = schedule_name,
        schedule_spec = schedule_spec,
        status = "running",
        frame_count = 0,
        path = result_path
    )
end

"""
    run_simulation(result::SimulationResultMetadata, schedule::Models.Model, ws_client::Union{HTTP.WebSocket, Nothing})

Execute a simulation and stream results.

Creates sink, executes schedule with sink as trace callback, flushes events,
counts frames, updates metadata, and notifies WebSocket client.

# Arguments
- `result::SimulationResultMetadata`: Result metadata (contains path for storage)
- `schedule::Models.Model`: Pre-constructed Model to execute
- `ws_client::Union{HTTP.WebSocket, Nothing}`: WebSocket client for streaming
"""
function run_simulation(result::SimulationResultMetadata, schedule::Models.Model, ws_client::Union{HTTP.WebSocket, Nothing})
    @info "[Simulation] Starting simulation" id=result.id schedule=result.schedule_name

    sink = StreamingSink.StreamingSimulationSink(
        location = result.path,
        ws_client = ws_client
    )

    state = Models.FlatState()

    try
        # Execute schedule with sink as trace callback
        @info "[Simulation] Executing schedule" id=result.id
        schedule(state, Inf; trace = sink, record = true)

        # Flush remaining buffered events and stream frames
        @info "[Simulation] Flushing events" id=result.id
        StreamingSink.flush!(sink)

        # Count frames from Arrow files
        @info "[Simulation] Counting frames" id=result.id
        frame_count = _count_frames_in_result(result.path)
        @info "[Simulation] Frame count" id=result.id frames=frame_count

        # Update metadata with final status
        @info "[Simulation] Updating metadata" id=result.id status="completed" frames=frame_count
        update_result_metadata(
            result.path;
            status = "completed",
            frame_count = frame_count
        )

        # Notify WebSocket client of completion
        if !isnothing(ws_client)
            @info "[Simulation] Notifying WebSocket client" id=result.id
            send(ws_client, JSON.json(Dict("type" => "completed", "id" => result.id, "frame_count" => frame_count)))
        end
        @info "[Simulation] Completed successfully" id=result.id
    catch e
        @error "[Simulation] Error during execution" id=result.id exception=string(e) stacktrace=stacktrace(catch_backtrace())
        update_result_metadata(
            result.path;
            status = "error",
            frame_count = 0,
            error = string(e)
        )
        if !isnothing(ws_client)
            send(ws_client, JSON.json(Dict("type" => "error", "id" => result.id, "error" => string(e))))
        end
        rethrow()
    end
end

"""
    _count_frames_in_result(result_path::String)::Int

Internal: count frames by reading Arrow event files.

Each unique (episode_i, time) pair represents one frame.
"""
function _count_frames_in_result(result_path::String)::Int
    frame_count = 0
    all_files = readdir(result_path)
    @debug "[Simulation] Reading result directory" path=result_path files=all_files

    for file in all_files
        if startswith(file, "events") && endswith(file, ".stream.arrow")
            events_file = joinpath(result_path, file)
            @debug "[Simulation] Counting frames in Arrow file" file=file
            events_table = Arrow.Table(events_file)
            unique_states = Set()
            for (i_val, t_val) in zip(events_table.i, events_table.t)
                push!(unique_states, (i_val, t_val))
            end
            file_frames = length(unique_states)
            frame_count += file_frames
            @debug "[Simulation] Frames in file" file=file count=file_frames total=frame_count
        end
    end
    @info "[Simulation] Total frames counted" total=frame_count
    return frame_count
end

# ============================================================================
# Metadata Management
# ============================================================================



"""
    update_result_metadata(result_path::String; status::String, frame_count::Int,
                          error::Union{String, Nothing}=nothing)

Update result metadata status and frame count (after simulation completion).

Only modifies metadata.json, preserves schedule.json already written.
"""
function update_result_metadata(result_path::String; status::String, frame_count::Int,
                                error::Union{String, Nothing}=nothing)
    metadata_file = joinpath(result_path, "metadata.json")

    if !isfile(metadata_file)
        @warn "[Simulation] Metadata file not found" path=result_path
        return
    end

    @debug "[Simulation] Reading metadata" file=metadata_file
    metadata = JSON.parsefile(metadata_file)
    @debug "[Simulation] Updating metadata fields" status=status frame_count=frame_count has_error=!isnothing(error)

    metadata["status"] = status
    metadata["frame_count"] = frame_count

    if !isnothing(error)
        metadata["error"] = error
    end

    open(metadata_file, "w") do f
        JSON.print(f, metadata, 2)
    end
end

# ============================================================================
# Loading Results
# ============================================================================

"""
    load_result_metadata(simulation_id::String)::Union{SimulationResultMetadata, Nothing}

Load simulation result metadata from disk without frames.

Returns nothing if result not found.
"""
function load_result_metadata(simulation_id::String)::Union{SimulationResultMetadata, Nothing}
    result_path = get_result_path(simulation_id)

    if !isdir(result_path)
        return nothing
    end

    metadata_file = joinpath(result_path, "metadata.json")
    if !isfile(metadata_file)
        return nothing
    end

    metadata = JSON.parsefile(metadata_file)

    # Parse creation time from id (ISO 8601 timestamp)
    created_at = try
        Dates.DateTime(metadata["id"], "yyyy-mm-ddTHH:MM:SS.sss")
    catch
        now()
    end

    # Load schedule spec from file
    schedule_spec = ""
    schedule_file = joinpath(result_path, "schedule.json")
    if isfile(schedule_file)
        schedule_spec = read(schedule_file, String)
    end

    return SimulationResultMetadata(
        id = metadata["id"],
        created_at = created_at,
        schedule_name = get(metadata, "schedule_name", ""),
        schedule_spec = schedule_spec,
        status = metadata["status"],
        error = get(metadata, "error", nothing),
        frame_count = metadata["frame_count"],
        path = result_path
    )
end

"""
    load_result(simulation_id::String)::Union{SimulationResult, Nothing}

Load simulation result with metadata and frames.

Returns nothing if result not found.
"""
function load_result(simulation_id::String)::Union{SimulationResult, Nothing}
    metadata = load_result_metadata(simulation_id)
    isnothing(metadata) && return nothing
    timeseries = load_timeseries_from_result(metadata.path)
    return SimulationResult(metadata, data = SimulationData(timeseries = timeseries))
end

# ============================================================================
# Listing Results
# ============================================================================

"""
    list_results(; status::Union{String, Nothing}=nothing)::Vector{SimulationResultMetadata}

List all stored simulation results.

# Arguments
- `status::String`: Filter by status ("running", "completed", "error"), or nothing for all

# Returns
- `Vector{SimulationResultMetadata}`: Sorted by creation time (newest first)
"""
function list_results(; status::Union{String, Nothing}=nothing)::Vector{SimulationResultMetadata}
    results_path = results_dir()

    if !isdir(results_path)
        return SimulationResultMetadata[]
    end

    results = SimulationResultMetadata[]

    for dir_entry in readdir(results_path; join=true)
        if isdir(dir_entry)
            sim_id = basename(dir_entry)
            result = load_result_metadata(sim_id)

            if !isnothing(result)
                if isnothing(status) || result.status == status
                    push!(results, result)
                end
            end
        end
    end

    # Sort by creation time (newest first)
    sort!(results; by=r -> r.created_at, rev=true)

    return results
end

# ============================================================================
# Deleting Results
# ============================================================================

"""
    delete_result(simulation_id::String)::Bool

Delete a stored simulation result and all associated files.

Returns true if successful, false if result not found.
"""
function delete_result(simulation_id::String)::Bool
    result_path = get_result_path(simulation_id)

    if !isdir(result_path)
        return false
    end

    rm(result_path; recursive=true)
    return true
end

# ============================================================================
# Helpers
# ============================================================================

"""
    load_timeseries_from_result(result_path::String)::Dict{Symbol, Dict{String, Vector{Tuple{Float64, Int}}}}

Load and convert events from Arrow files to timeseries format.

Groups events by species → path and returns a nested dictionary where each
path's timeseries is a sorted vector of (time, count) tuples.
"""
function load_timeseries_from_result(result_path::String)::Dict{Symbol, Dict{String, Vector{Tuple{Float64, Int}}}}
    timeseries = Dict{Symbol, Dict{String, Vector{Tuple{Float64, Int}}}}()

    if !isdir(result_path)
        @warn "Result directory not found" result_path
        return timeseries
    end

    # Load path mapping and time bounds from index.arrow
    (i_to_path, path_time_bounds) = _load_index_mapping(result_path)

    # Look for events*.stream.arrow files
    for file in readdir(result_path)
        if startswith(file, "events") && endswith(file, ".stream.arrow")
            events_file = joinpath(result_path, file)

            events_table = Arrow.Table(events_file)

            # Group events by (species_symbol, execution_path)
            for (i, t, name, value) in zip(events_table.i, events_table.t, events_table.name, events_table.value)
                path = get(i_to_path, i, string(i))
                species_symbol = name  # name is already a Symbol from Arrow

                if !haskey(timeseries, species_symbol)
                    timeseries[species_symbol] = Dict{String, Vector{Tuple{Float64, Int}}}()
                end
                if !haskey(timeseries[species_symbol], path)
                    timeseries[species_symbol][path] = Tuple{Float64, Int}[]
                end
                push!(timeseries[species_symbol][path], (t, value))
            end
        end
    end

    # Sort each timeseries by time
    for species in values(timeseries)
        for path_data in values(species)
            sort!(path_data; by = x -> x[1])
        end
    end

    # Add artificial final timepoint at the end of each path
    for species_symbol in keys(timeseries)
        for path in keys(timeseries[species_symbol])
            if !isempty(timeseries[species_symbol][path])
                _, max_time = get(path_time_bounds, path, (0.0, 0.0))
                if max_time > 0.0
                    last_time, last_count = timeseries[species_symbol][path][end]
                    if last_time < max_time
                        push!(timeseries[species_symbol][path], (max_time, last_count))
                    end
                end
            end
        end
    end

    @info "Converted to timeseries" result_path series_count=length(timeseries)
    return timeseries
end

"""
    _load_index_mapping(result_path::String)::Tuple{Dict{Int, String}, Dict{String, Tuple{Float64, Float64}}}

Load episode index to path mapping from index.arrow and time bounds from events.

Returns:
- `i_to_path::Dict{Int, String}`: Maps episode index to execution path
- `path_time_bounds::Dict{String, Tuple{Float64, Float64}}`: Maps path to (min_time, max_time)

Returns empty dicts if files not found or can't be read.
"""
function _load_index_mapping(result_path::String)::Tuple{Dict{Int, String}, Dict{String, Tuple{Float64, Float64}}}
    i_to_path = Dict{Int, String}()
    path_time_bounds = Dict{String, Tuple{Float64, Float64}}()

    index_file = joinpath(result_path, "index.arrow")
    if !isfile(index_file)
        @debug "No index.arrow found" result_path
        return (i_to_path, path_time_bounds)
    end

    index_table = Arrow.Table(index_file)
    for idx in eachindex(index_table.i)
        episode_i = index_table.i[idx]
        path = string(index_table.path[idx])
        i_to_path[episode_i] = path
    end
    @debug "Loaded path mapping from index" result_path path_count=length(i_to_path)

    # Extract time bounds for each path from events files
    for file in readdir(result_path)
        if startswith(file, "events") && endswith(file, ".stream.arrow")
            events_file = joinpath(result_path, file)
            events_table = Arrow.Table(events_file)

            for (i, t) in zip(events_table.i, events_table.t)
                path = get(i_to_path, i, string(i))
                if !haskey(path_time_bounds, path)
                    path_time_bounds[path] = (t, t)
                else
                    min_t, max_t = path_time_bounds[path]
                    path_time_bounds[path] = (min(min_t, t), max(max_t, t))
                end
            end
        end
    end
    @debug "Extracted time bounds" result_path path_count=length(path_time_bounds)

    return (i_to_path, path_time_bounds)
end

# ============================================================================
# Frame Loading
# ============================================================================

"""
    load_frames_from_result(result_path::String)::Vector{SimulationFrame}

Load SimulationFrame objects from Arrow event files.

Reads events_*.arrow files, groups events by (episode, time), and reconstructs
SimulationFrame objects. Returns empty vector if files not found.

# Arguments
- `result_path::String`: Path to the simulation result directory

# Returns
- `Vector{SimulationFrame}`: Frames sorted by (path, time)

# Storage Format
events_*.arrow files have columns:
- `i::Int64`: Episode index (execution path identifier)
- `t::Float64`: Time point
- `name::Symbol`: Species/event name
- `value::Int64`: Species count value
"""
function load_frames_from_result(result_path::String)::Vector{SimulationFrame}
    frames = SimulationFrame[]

    if !isdir(result_path)
        @warn "Result directory not found" result_path
        return frames
    end

    # Load path mapping and time bounds from index.arrow
    (i_to_path, _) = _load_index_mapping(result_path)

    # Look for events*.stream.arrow files
    for file in readdir(result_path)
        if startswith(file, "events") && endswith(file, ".stream.arrow")
            events_file = joinpath(result_path, file)

            events_table = Arrow.Table(events_file)

            # Group events by (episode_i, time) for reconstruction
            events_by_state = Dict{Tuple{Int, Float64}, Vector}()

            for (i, t, name, value) in zip(events_table.i, events_table.t, events_table.name, events_table.value)
                key = (i, t)
                if !haskey(events_by_state, key)
                    events_by_state[key] = []
                end
                push!(events_by_state[key], (i=i, t=t, name=name, value=value))
            end

            # Reconstruct frames from grouped events
            for ((episode_i, t), events) in events_by_state
                path = get(i_to_path, episode_i, string(episode_i))
                counts = Dict{String, Int}()
                for event in events
                    counts[String(event.name)] = event.value
                end
                frame = SimulationFrame(path=path, t=t, counts=counts)
                push!(frames, frame)
            end
        end
    end

    # Sort by (path, time)
    sort!(frames; by = f -> (f.path, f.t))

    @info "Loaded frames from events" result_path frame_count=length(frames)
    return frames
end

end # module Simulation
