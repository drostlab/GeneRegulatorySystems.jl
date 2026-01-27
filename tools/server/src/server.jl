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
include("simulation.jl")
include("types.jl")

# Use submodules
using .ScheduleStorage
using .StreamingSink
using .Simulation
using .SchemaTypes
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


### Simulation service

# list all simulation results metadata
@get "/simulations" function()
    return Simulation.list_results()::Vector{Simulation.SimulationResultMetadata}
end

# get simulation metadata for result
@get "/simulations/{id}/metadata" function(_, id::String)
    result = Simulation.load_result_metadata(id)
    isnothing(result) && throw("Result not found")

    return result::Simulation.SimulationResultMetadata
end

# get full simulation result with data (metadata + frames from Arrow files)
@get "/simulations/{id}" function(_, id::String)
    result = Simulation.load_result(id)
    isnothing(result) && throw("Result not found")
    return result::Simulation.SimulationResult
end

const ws_client = Ref{Union{Nothing, HTTP.WebSocket}}()
const WS_LOCK = ReentrantLock()
const simulation_task = Ref{Union{Nothing, Task}}()

@websocket "/ws" function(ws::HTTP.WebSocket)
    @info "WebSocket client connected"
    lock(WS_LOCK) do
        ws_client[] = ws
    end

    for msg in ws
        @debug "[WebSocket] Received message" msg
    end

    lock(WS_LOCK) do
        ws_client[] = nothing
    end
    close(ws)
    @info "WebSocket client disconnected"
end

@kwdef struct RunSimulationRequest
    schedule_name::String
    schedule_spec::String
end
# start a simulation run
@post "/simulations/run" function(req, data::Json{RunSimulationRequest})
    # Load and validate model from spec (throws on invalid spec)
    model = Simulation.load_model_from_spec(data.payload.schedule_spec)

    # Prepare result directory and metadata
    res_metadata = Simulation.prepare_result(data.payload.schedule_name, data.payload.schedule_spec)

    # Get current websocket client
    current_ws = lock(WS_LOCK) do
        ws_client[]
    end

    # Spawn async simulation task with constructed model
    simulation_task[] = @async Simulation.run_simulation(res_metadata, model, current_ws)

    # Return immediately with status=running
    return res_metadata::Simulation.SimulationResultMetadata
end



end
