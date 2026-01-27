"""
    ScheduleStorage

Manages persistent storage of schedules in two categories:
- examples/: Read-only example schedules (pre-populated in storage)
- user/: User-created schedules (editable)

All schedule files are stored flat (no subdirectories) as {name}.json.
"""
module ScheduleStorage

using GeneRegulatorySystems
using GeneRegulatorySystems.Models
using GeneRegulatorySystems.Models.Scheduling
using JSON
using Logging

export list_all_schedules, get_schedule_spec, save_user_schedule,
       schedule_exists, schedules_dir, get_schedule_path, delete_user_schedule

# ============================================================================
# Paths
# ============================================================================

"""
    schedules_dir()

Get the schedules storage directory, creating it if needed.
Schedules are stored relative to the server module directory.
"""
function schedules_dir()
    dir = joinpath(@__DIR__, "..", "storage", "schedules")
    mkpath(dir)
    return dir
end

"""
    get_schedule_path(name::String, source::String)

Get the file path for a schedule.

# Arguments
- `name::String`: Schedule name (without .schedule.json extension)
- `source::String`: "examples" or "user"

# Returns
- `String`: Full path to {name}.schedule.json
"""
function get_schedule_path(name::String, source::String)
    joinpath(schedules_dir(), source, "$(name).schedule.json")
end

# ============================================================================
# Listing
# ============================================================================

"""
    list_all_schedules()::Vector{String}

List all available schedule keys in format "source/name".

Returns schedules from both examples/ and user/ directories.
Strips the .schedule.json extension and prefixes with source.
"""
function list_all_schedules()::Vector{String}
    schedules = String[]

    for source in ["examples", "user"]
        dir = joinpath(schedules_dir(), source)
        if isdir(dir)
            for file in readdir(dir)
                if endswith(file, ".schedule.json")
                    # Strip .schedule.json extension
                    name = replace(file, ".schedule.json" => "")
                    push!(schedules, "$(source)/$(name)")
                end
            end
        end
    end

    return sort!(unique(schedules))
end

"""
    schedule_exists(name::String, source::String)::Bool

Check if a schedule exists.

# Arguments
- `name::String`: Schedule name (without extension)
- `source::String`: "examples" or "user"

# Returns
- `Bool`: true if schedule file exists
"""
function schedule_exists(name::String, source::String)::Bool
    path = get_schedule_path(name, source)
    isfile(path)
end

# ============================================================================
# Loading
# ============================================================================

"""
    get_schedule_spec(name::String, source::String)::Union{String, Nothing}

Load raw schedule JSON from storage.

# Arguments
- `name::String`: Schedule name (without extension)
- `source::String`: Source source ("examples" or "user")

# Returns
- `String`: Raw JSON content
- `Nothing`: If schedule not found
"""
function get_schedule_spec(name::String, source::String)::Union{String, Nothing}
    if schedule_exists(name, source)
        path = get_schedule_path(name, source)
        return read(path, String)
    end

    @warn "Schedule not found" name source
    return nothing
end

# ============================================================================
# Saving
# ============================================================================

"""
    save_user_schedule(name::String, json::String)::Bool

Save a schedule to user storage.

# Arguments
- `name::String`: Schedule name (without extension)
- `json::String`: Schedule JSON content (should already be formatted by frontend)

# Returns
- `Bool`: true if successful
"""
function save_user_schedule(name::String, json::String)::Bool
    try
        # Create user directory if needed
        user_dir = joinpath(schedules_dir(), "user")
        mkpath(user_dir)

        # Write file (frontend already handles formatting)
        path = get_schedule_path(name, "user")
        open(path, "w") do f
            write(f, json)
        end

        @debug "Saved user schedule" name path
        return true
    catch e
        @error "Failed to save user schedule" name exception=e
        return false
    end
end

"""
    delete_user_schedule(name::String)::Bool

Delete a user schedule.

# Arguments
- `name::String`: Schedule name (without extension)

# Returns
- `Bool`: true if successful or file doesn't exist
"""
function delete_user_schedule(name::String)::Bool
    try
        path = get_schedule_path(name, "user")
        if isfile(path)
            rm(path)
            @debug "Deleted user schedule" name
        end
        return true
    catch e
        @error "Failed to delete user schedule" name exception=e
        return false
    end
end

end # module ScheduleStorage
