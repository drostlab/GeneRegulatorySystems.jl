module ExperimentTool

if nameof(parentmodule(@__MODULE__)) == :GeneRegulatorySystemsTools
    @eval using GeneRegulatorySystemsTools: Common
else
    include("$(@__DIR__)/../common.jl")
end

using .Common: repository_version, artifact

using Chain
using DataFrames
using LoggingExtras
import ProgressLogging
using TerminalLoggers: TerminalLogger
using UUIDs

using Base: @kwdef
import Dates

# NOTE: This module lazily imports additional modules in `main`.

abstract type ProgressLogger <: AbstractLogger end

Logging.min_enabled_level(::ProgressLogger) =
    GeneRegulatorySystems.Scheduling.Progress

Logging.shouldlog(::ProgressLogger, level, module_, _group, _id) =
    level == Scheduling.Progress && (
        module_ == Scheduling ||
        module_ == Models.SciML ||
        module_ == ExperimentTool
    )

struct SimpleProgressLogger <: ProgressLogger end

function Logging.handle_message(
    ::SimpleProgressLogger,
    _level,
    message::Symbol,
    _rest...;
    at,
    todo = nothing,
    done = nothing,
)
    if message == :done
        @info "$at done"
    elseif message == :saved
        @info "Saved $done slices into '$at'"
    end
end

@kwdef struct BarProgressLogger <: ProgressLogger
    ids::Dict{String, UUID} = Dict{String, UUID}()
    todo::Dict{String, Real} = Dict{String, Real}()
end

function Logging.handle_message(
    logger::BarProgressLogger,
    _level,
    message::Symbol,
    _rest...;
    at,
    todo = nothing,
    done = 0,
)
    if message == :saved
        @info "Saved $done slices into '$at'"
        return
    end

    id = get!(uuid4, logger.ids, at)

    if message == :done || message == :advanced
        @info ProgressLogging.Progress(id, done = true, name = "$at done")
        delete!(logger.ids, at)
        delete!(logger.todo, at)
        return
    end

    if todo isa Real && isfinite(todo)
        logger.todo[at] = todo
    end

    if todo isa Real && !isfinite(todo) && done <= 0
        # To unclutter the bar stack we will pretend we are done with this path
        # when we freshly step into a Scope. If we make a second step in this
        # scope, we will just spawn a new bar with that log message.
        @info ProgressLogging.Progress(id, done = true, name = "$at ...")
        return
    end

    formatted_done =
        string(done isa AbstractFloat ? round(done, digits = 1) : done)
    todo = @something(todo, get(logger.todo, at, nothing), Some(nothing))
    fraction = nothing
    if todo === nothing
        details = ""
    elseif todo isa Real
        if isfinite(todo)
            fraction = done / todo
            details = "($formatted_done/$todo)"
        else
            details = "($formatted_done))"
        end
    else
        details = "($todo)"
    end
    action = lpad(message, 10)
    description = join(filter(!isempty, [action, at, details]), ' ')
    @info ProgressLogging.Progress(id, fraction, name = description)
end

function map_artifacts(paths)
    preliminary_map = Dict(p => basename(p) for p in paths)
    if allunique(vcat(artifact(:specification), values(preliminary_map)...))
        return preliminary_map
    else
        return Dict(p => "_$(i)_$(basename(p))" for (i, p) in enumerate(paths))
    end
end

function assert_compatible_versions(specification)
    if (specification[:_julia_version] != "v$VERSION")
        @error(
            "Experiment was prepared with a different Julia version.",
            specification.bindings[:_julia_version],
            "v$VERSION",
        )
        @info "This is disallowed to ensure reproducibility."
        throw(:help)
    end

    if (specification[:_version] != repository_version())
        @error(
            "Experiment was prepared with a different " *
            "GeneRegulatorySystems.jl version.",
            specification[:_version],
            repository_version(),
        )
        @info "This is disallowed to ensure reproducibility."
        throw(:help)
    end
end

function prepare!(; location, specifications, seed)
    specification_path = artifact(:specification; prefix = location)
    if ispath(specification_path)
        @error(
            "Cannot prepare experiment, specification already exists.",
            specification_path,
        )
        throw(:help)
    elseif isempty(specifications)
        @error "No specifications given to be prepared."
        throw(:help)
    else
        paths = realpath.(specifications)
        artifacts = map_artifacts(paths)
        wrapped = [
            Dict(:< => basename("$(location)$(artifacts[p])"))
            for p in paths
        ]

        mkpath(dirname(specification_path))
        for (source, target) in artifacts
            cp(source, "$(location)$target"; follow_symlinks = true)
        end
        open(specification_path, "w") do file
            JSON.print(
                file,
                merge(
                    Dict(
                        :seed => seed,
                        :_version => repository_version(),
                        :_julia_version => "v$VERSION",
                    ),
                    if length(wrapped) == 1
                        Dict(:step => only(wrapped))
                    else
                        Dict(:step => wrapped, :branch => true)
                    end,
                ),
                4,
            )
        end
    end
end

@kwdef mutable struct Sink
    location::String
    i::Int = 0
    index = []
    threshold::Int = 100000
    channels::Dict{String, DataFrame} = Dict{String, DataFrame}()
end

function flush!(sink::Sink)
    for into in keys(sink.channels)
        flush!(sink, into)
    end

    index = artifact(:index; prefix = sink.location)
    Arrow.write(index, sink.index, dictencode = true)
end

function flush!(sink::Sink, into)
    segment = pop!(sink.channels, into)
    segments = artifact(:segments, into, prefix = sink.location)
    if isfile(segments)
        Arrow.append(segments, segment)
    else
        Arrow.write(segments, segment, file = false)
    end
    @logmsg(Scheduling.Progress, :saved, at = segments, done = nrow(segment))
end

function (sink::Sink)(into, state; path, primitive!, from, _...)
    sink.i += 1

    to = Models.t(state)
    if primitive!.skip > 0.0
        from = to
    end
    model = primitive!.path
    label = get(primitive!.bindings, :label, "")
    push!(sink.index, (; sink.i, path, from, to, model, label, into))

    segment = @chain begin
        state
        Models.table(sorted = true)
        DataFrame
        insertcols(1, :i => sink.i)
    end

    if haskey(sink.channels, into)
        append!(sink.channels[into], segment, cols = :orderequal)
    else
        sink.channels[into] = copy(segment)
    end

    prod(size(sink.channels[into])) > sink.threshold && flush!(sink, into)
end

function with_progress(run!, progress::Symbol)
    if progress == :bars && stdout isa Base.TTY
        with_logger(run!, TeeLogger(current_logger(), BarProgressLogger()))
    elseif progress == :simple
        with_logger(run!, TeeLogger(current_logger(), SimpleProgressLogger()))
    else
        run!()
    end
end

function simulate!(; location, progress, dry)
    load(path) = JSON.parsefile(
        "$(dirname(location))/$path";
        dicttype = Dict{Symbol, Any}
    )

    function dryrun(primitive!, x, Δt; path, into, _...)
        modelname = nameof(typeof(primitive!.f!))
        maybe_source = primitive!.path == path ? "" : " ($(primitive!.path))"
        isinterval = isfinite(Δt) && 0.0 < Δt
        interval = isinterval ? "from $(x.t) to $(x.t + Δt)" : "at $(x.t)"
        maybe_into =
            if into === nothing
                ""
            elseif isinterval && 0.0 < primitive!.skip
                ", record final into '$into'"
            else
                ", record into '$into'"
            end

        @info "$path: $modelname$maybe_source $interval$maybe_into"
    end

    specification = load(basename(artifact(:specification; prefix = location)))
    assert_compatible_versions(specification)
    schedule! = Schedule(specification = Specification(specification))

    if dry
        progress = :none
    end

    with_progress(progress) do
        state = Models.FlatState()
        state = Models.Plumbing.Seed(specification[:seed])(state)
        sink = Sink(; location)
        schedule!(state; load, dump = sink, dryrun = dry ? dryrun : nothing)
        flush!(sink)
    end
end

function main(;
    location,
    prepare,
    simulate,
    progress,
    dry,
    seed,
    specifications,
)
    global_logger(TerminalLogger())

    timestamp = Dates.now()
    location = replace(location, "{TIMESTAMP}" => timestamp)

    if !any([prepare, simulate])
        prepare = true
        simulate = true
    end

    @eval import JSON
    prepare && Base.invokelatest(prepare!; location, specifications, seed)

    @eval using GeneRegulatorySystems
    @eval import Arrow
    simulate && Base.invokelatest(simulate!; location, progress, dry)

    nothing
end

end
