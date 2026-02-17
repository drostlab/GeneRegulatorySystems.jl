module server

using Oxygen; @oxidize
using HTTP
using HTTP.WebSockets
using JSON
using Logging
using Dates
using Arrow

using GeneRegulatorySystems
using GeneRegulatorySystems.Models
using GeneRegulatorySystems.Models.Scheduling

# Include submodules
include("streaming_sink.jl")
include("schedule_storage.jl")
include("schedule_visualisation.jl")
include("simulation_controller.jl")
include("simulation.jl")

# Use submodules
using .ScheduleStorage
using .StreamingSink
using .Simulation
using .SimulationController_
using .ScheduleVisualization
using Base: @kwdef



### Schedule service

# return available schedule keys (in format "source/name")
@get "/schedules" function()
    ScheduleStorage.list_all_schedules()::Vector{String}
end

# return spec for a given schedule key (in string format)
@get "/schedules/{source}/{name}/spec" function(_, source::String, name::String)
    ScheduleStorage.get_schedule_spec(name, source)::String
end

# return full schedule object for a stored schedule (includes validation and visualization data)
@get "/schedules/{source}/{name}" function(_, source::String, name::String)
    spec_str = ScheduleStorage.get_schedule_spec(name, source)
    isnothing(spec_str) && throw("Schedule not found")
    return ScheduleVisualization.reify_schedule(spec_str, name=name, source=source)::ScheduleVisualization.ReifiedSchedule
end

@kwdef struct LoadScheduleRequest
    schedule_name::String
    schedule_spec::String
end
# validate and generate visualization for schedule spec
@post "/schedules/load" function(req, data::Json{LoadScheduleRequest})
    return ScheduleVisualization.reify_schedule(data.payload.schedule_spec, name=data.payload.schedule_name)::ScheduleVisualization.ReifiedSchedule
end

@kwdef struct UploadScheduleRequest
    schedule_name::String
    schedule_spec::String
end
# upload and save schedule to user storage
@post "/schedules/upload" function(req, data::Json{UploadScheduleRequest})
    ScheduleStorage.save_user_schedule(data.payload.schedule_name, data.payload.schedule_spec)
    return ScheduleVisualization.reify_schedule(data.payload.schedule_spec, name=data.payload.schedule_name, source="user")::ScheduleVisualization.ReifiedSchedule
end

# extract network for a stored schedule by model_path
@get "/schedules/{source}/{name}/network" function(req, source::String, name::String)
    model_path = HTTP.queryparams(HTTP.URI(req.target))["model_path"]
    spec_str = ScheduleStorage.get_schedule_spec(name, source)
    isnothing(spec_str) && throw("Schedule not found")
    return ScheduleVisualization.extract_network_for_model_path(spec_str, model_path)::ScheduleVisualization.Network
end

@kwdef struct NetworkFromSpecRequest
    schedule_spec::String
    model_path::String
end
# extract network from spec + model_path
@post "/schedules/network" function(req, data::Json{NetworkFromSpecRequest})
    return ScheduleVisualization.extract_network_for_model_path(data.payload.schedule_spec, data.payload.model_path)::ScheduleVisualization.Network
end

@kwdef struct UnionNetworkRequest
    schedule_spec::String
    segments::Vector{ScheduleVisualization.TimelineSegment}
end
# extract union network across all model paths
@post "/schedules/union-network" function(req, data::Json{UnionNetworkRequest})
    return ScheduleVisualization.extract_union_network(data.payload.schedule_spec, data.payload.segments)::ScheduleVisualization.UnionNetwork
end


### Simulation service

# list all simulation results
@get "/simulations" function()
    return Simulation.list_results()::Vector{Simulation.SimulationResult}
end

# get simulation result (metadata only, no frames)
@get "/simulations/{id}" function(_, id::String)
    result = Simulation.load_result(id)
    isnothing(result) && throw("Result not found")
    return result::Simulation.SimulationResult
end

@kwdef struct TimeseriesRequest
    species::Vector{String}
end
# get filtered timeseries for specific species
@post "/simulations/{id}/timeseries" function(req, id::String, data::Json{TimeseriesRequest})
    result = Simulation.load_result(id)
    isnothing(result) && throw("Result not found")
    species_filter = Set(Symbol.(data.payload.species))
    timeseries = Simulation.load_timeseries_for_species(result.path, species_filter)
    return Simulation.SimulationData(; timeseries)
end

const ws_client = Ref{Union{Nothing, HTTP.WebSocket}}(nothing)
const WS_LOCK = ReentrantLock()
const simulation_task = Ref{Union{Nothing, Task}}(nothing)
const active_controller = Ref{Union{Nothing, SimulationController}}(nothing)

@websocket "/ws" function(ws::HTTP.WebSocket)
    @info "WebSocket client connected"
    lock(WS_LOCK) do
        ws_client[] = ws
    end

    for raw_msg in ws
        _handle_ws_message(raw_msg)
    end

    lock(WS_LOCK) do
        ws_client[] = nothing
    end
    close(ws)
    @info "WebSocket client disconnected"
end

function _handle_ws_message(raw::String)
    msg = JSON.parse(raw)
    msg_type = haskey(msg, "type") ? msg["type"] : ""
    @info "[WS] Received message" type=msg_type
    ctrl = active_controller[]

    if msg_type == "subscribe"
        species = haskey(msg, "species") ? msg["species"] : String[]
        if !isnothing(ctrl)
            subscribe_genes!(ctrl, convert(Vector{String}, species))
            @debug "[WS] Subscribed to species" count=length(species)
        end
    elseif msg_type == "pause"
        if !isnothing(ctrl)
            pause!(ctrl)
            Simulation.update_result_metadata(ctrl.result_path; status="paused")
        end
    elseif msg_type == "resume"
        if !isnothing(ctrl)
            resume!(ctrl)
            Simulation.update_result_metadata(ctrl.result_path; status="running")
        end
    else
        @warn "[WS] Unknown message type" msg_type
    end
end

@kwdef struct RunSimulationRequest
    schedule_name::String
    schedule_spec::String
    max_time::Float64 = 0.0
end

# start a simulation run (async, streamed via WS)
@post "/simulations/run" function(req, data::Json{RunSimulationRequest})
    # Load and validate model from spec (throws on invalid spec)
    model = Simulation.load_model_from_spec(data.payload.schedule_spec)

    max_time = data.payload.max_time

    # Prepare result directory and metadata
    result = Simulation.prepare_result(data.payload.schedule_name, data.payload.schedule_spec; max_time)

    # Get current websocket client
    current_ws = lock(WS_LOCK) do
        ws_client[]
    end

    # Create simulation controller for pause/resume and gene subscriptions
    ctrl = SimulationController(
        result_path = result.path,
        simulation_id = result.id,
        ws_client = current_ws
    )
    active_controller[] = ctrl

    # Spawn async simulation task
    simulation_task[] = @async begin
        Simulation.run_simulation(result, model, current_ws; controller = ctrl)
        active_controller[] = nothing
    end

    # Return immediately with status=running
    return result::Simulation.SimulationResult
end

end
