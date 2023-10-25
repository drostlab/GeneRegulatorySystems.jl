module Scheduling

using ...Conversion: cast
using ..Models: Models, Model, FlatState, Branched
using ..Models.Plumbing: Pass
using ...Specifications: Specifications
using ...Specifications: Each
using ...Specifications: List
using ...Specifications: Load
using ...Specifications: Scope
using ...Specifications: Sequence
using ...Specifications: Slice
using ...Specifications: Specification
using ...Specifications: Template

using Base: @kwdef
using Logging: LogLevel, @logmsg
using Random

Progress = LogLevel(-2)

struct Locator
    path::String
end

Specifications.paste(locator::Locator) =
    join("-$s" for s in split(locator.path, r"[+-/]") if length(s) > 0)

#=
struct Locator
    path::Vector{Int}
end

const LOCATOR_PATTERN = r"@(?<path>[/\d]*)"

function Base.show(io::IO, ::MIME"text/plain", locator::Locator)
    segments = (s > 0 ? "/$s" : "/" for s in locator.path)
    write(io, "@$(join(segments))")
end

function Base.parse(::Type{Locator}, locator::AbstractString)
    segments = split(match(LOCATOR_PATTERN, locator)[:path], '/')
    Locator([isempty(s) ? 0 : parse(Int, s) for s in segments][2:end])
end
=#

@kwdef struct Primitive <: Model{Any}
    f!::Model
    skip::Float64 = 0.0
    into::Union{String, Nothing}
    path::String
    bindings::Dict{Symbol, Any}
end

function (primitive!::Primitive)(
    x,
    Δt::Float64;
    path,
    trace = nothing,
    dryrun = nothing,
    context...,
)
    f! = primitive!.f!
    if primitive!.skip > 0.0
        Δt = min(Δt, primitive!.skip)
    end

    if dryrun !== nothing
        x = cast(FlatState, x)
        if primitive!.f! isa Models.Instant
            Δt = 0.0
        end
        dryrun(primitive!, x, Δt; path, primitive!.into, context...)
        if isfinite(Δt)
            x.t += Δt
        end
        return x
    end

    @logmsg(
        Progress,
        :adapting,
        at = path,
        todo = "$(nameof(typeof(x))) to $(nameof(typeof(f!))) \
            ($(primitive!.path))",
    )
    x = Models.adapt(x, f!)
    from = Models.t(x)

    @logmsg Progress :advancing at = path
    if trace === nothing
        f!(x, Δt; path, context...)
    elseif primitive!.skip > 0.0
        f!(x, Δt; path, context...)
        trace(nothing, x; path, primitive!, from)
        if primitive!.into !== nothing
            trace(primitive!.into, x; path, primitive!, from = Models.t(x))
        end
    else
        f!(x, Δt; path, context..., primitive!.into)
        trace(primitive!.into, x; path, primitive!, from)
    end

    @logmsg Progress :done at = path
    x
end

@kwdef struct Schedule{S <: Specification} <: Model{Any}
    specification::S
    bindings::Dict{Symbol, Any} = Dict{Symbol, Any}(
        :into => :channel,
        :channel => "",
    )
    branch::Bool = false
    path::String = ""
end

function sink(bindings::Dict{Symbol, Any})
    into = get(bindings, :into, nothing)
    if into == :channel
        into = get(bindings, :channel, nothing)
    end
    into
end

function descended(bindings::Dict{Symbol, Any}, segment)
    channel = get(bindings, :channel, nothing)
    merge(
        bindings,
        Dict(:channel => isnothing(channel) ? nothing : "$channel-$segment"),
    )
end

evaluate(template::Template; bindings) =
    Specifications.expand(template; bindings)
evaluate(x; _...) = x

model(template::Template; bindings, branch, path) =
    model(Specifications.expand(template; bindings); bindings, branch, path)

model(specification::Specification; bindings, branch, path) =
    Schedule(; specification, bindings, branch, path)

function model(f!::Model; bindings, branch, path)
    branch && error("cannot branch here: not a Sequence")
    Primitive(into = sink(bindings); f!, path, bindings)
end

function model(at::Float64; bindings, branch, path)
    branch && error("cannot branch here: not a Sequence")
    Primitive(
        f! = bindings[:do],
        skip = at,
        into = sink(bindings),
        path = "$(bindings[Symbol("^do")].path).do";
        bindings,
    )
end

models(list::List; bindings, path) = (
    model(
        specification,
        bindings = descended(bindings, i),
        branch = false,
        path = "$path$i"
    )
    for (i, specification) in enumerate(list.items)
)

models(each::Each; bindings, path) = (
    model(
        each.step,
        bindings = each.as == Symbol() ? bindings : merge(
            descended(bindings, i),
            Dict(each.as => evaluate(specification; bindings)),
        ),
        branch = false,
        path = "$path$i"
    )
    for (i, specification) in enumerate(evaluate(each.items; bindings))
)

function (f!::Schedule{Slice})(x, Δt::Float64; context...)
    path =
        if haskey(f!.bindings, :do)
            "$(f!.bindings[Symbol("^do")].path).do"
        else
            f!.path
        end
    model(
        get(f!.bindings, :do, Pass());
        f!.bindings,
        f!.branch,
        path
    )(x, Δt; context...)
end

(f!::Schedule{Template})(x, Δt::Float64; path, context...) =
    model(
        evaluate(f!.specification; f!.bindings);
        f!.bindings,
        f!.branch,
        path,
    )(x, Δt; path, context...)

function (f!::Schedule{Scope})(
    x = FlatState(randomness = Random.GLOBAL_RNG),
    Δt::Float64 = Inf;
    context...
)
    path = f!.path
    f!.branch && error("cannot branch here: not a Sequence")

    @logmsg Progress :preparing at = path
    x = Models.adapt(x, f!)  # potentially unwrap Branched
    bindings = merge(
        f!.specification.barrier ? Dict{Symbol, Any}() : f!.bindings,
        Dict{Symbol, Any}(
            name => evaluate(specification; f!.bindings)
            for (name, specification) in f!.specification.definitions
        ),
        Dict{Symbol, Any}(
            Symbol("^$name") => Locator(path)
            for name in keys(f!.specification.definitions)
        )
    )

    path′ = "$(f!.path)$(f!.specification.branch ? '/' : '+')"
    step! = model(
        f!.specification.step;
        bindings,
        f!.specification.branch,
        path = path′,
    )

    to = get(bindings, :to, Inf)
    Δt = min(Δt, to)
    done = 0.0
    @logmsg Progress :repeating at = path todo = Δt
    while 0.0 < Δt
        current = Models.t(x)
        x = step!(x, Δt; context..., path = path′)
        isfinite(Δt) || break
        advance = Models.t(x) - current
        0.0 < advance || error("cannot progress")
        Δt -= advance
        done += advance
        @logmsg Progress :repeating at = path done
    end

    @logmsg Progress :done at = path

    x
end

function (f!::Schedule{<:Sequence})(x, Δt::Float64; context...)
    path = f!.branch ? f!.path : "$(f!.path)-"
    @logmsg Progress :preparing at = path

    x = Models.adapt(x, f!)  # potentially unwrap Branched
    steps = models(f!.specification; f!.bindings, path)

    @logmsg Progress :iterating at = path todo = length(steps)
    if f!.branch
        x = Branched(x)
        for (i, step!) in enumerate(steps)
            x′ = Models.adapt(x.stem, step!, copy = true)
            x′ = step!(x′, Inf; context..., path = "$path$i")
            push!(x.branches, x′)
            @logmsg Progress :iterating at = path done = i
        end
    else
        for (i, step!) in enumerate(steps)
            current = Models.t(x)
            x = step!(x, Δt; context..., path = "$path$i")
            Δt -= Models.t(x) - current
            @logmsg Progress :iterating at = path done = i
        end
    end

    @logmsg Progress :done at = path

    x
end

function (f!::Schedule{Load})(x, Δt::Float64; load, context...)
    channel = get(f!.bindings, :channel, nothing)
    if channel !== nothing
        name = replace(f!.specification.path, r"(\.schedule)?(\.json)$" => "")
        channel = "$channel-$name"
    end
    Schedule(
        specification = Specification(
            load(f!.specification.path),
            bound = Set(keys(f!.bindings)),
        ),
        bindings = merge(f!.bindings, Dict(:channel => channel));
        f!.branch,
        f!.path,
    )(x, Δt; load, context..., f!.path)
end

end
