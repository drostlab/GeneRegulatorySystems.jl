module Scheduling

using ...Conversion: cast
using ..Models: Models, Model, FlatState, Branched
using ..Models.Plumbing: Pass
using ...Specifications:
    Specifications,
    Each,
    List,
    Load,
    Scope,
    Sequence,
    Slice,
    Specification,
    Template

using Logging: LogLevel, @logmsg
using Random

Progress = LogLevel(-2)

struct Locator
    path::String
end

Specifications.paste(locator::Locator) =
    join("-$s" for s in split(locator.path, r"[+-/]") if length(s) > 0)

@kwdef struct Primitive <: Model{Any}
    f!::Model
    skip::Float64 = 0.0
    into::Union{String, Nothing}
    path::String
    bindings::Dict{Symbol, Any}
end

Models.describe(primitive!::Primitive) = Models.describe(primitive!.f!)

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
        x = f!(x, Δt; path, context...)
    elseif primitive!.skip > 0.0
        x = f!(x, Δt; path, context...)
        trace(nothing, x; path, primitive!, from)
        if primitive!.into !== nothing
            trace(primitive!.into, x; path, primitive!, from = Models.t(x))
        end
    else
        x = f!(x, Δt; path, context..., primitive!.into)
        trace(primitive!.into, x; path, primitive!, from)
    end

    @logmsg Progress :done at = path
    x
end

@kwdef struct Schedule{S <: Specification} <: Model{Any}
    specification::S
    bindings::Dict{Symbol, Any} = Dict{Symbol, Any}(
        :seed => "",
        :into => "",
        :channel => "",
    )
    branch::Bool = false
    path::String = ""
end

Models.adapt(x, ::Schedule, _copy::Val{false}) = x

function sink(bindings::Dict{Symbol, Any})
    into = get(bindings, :into, nothing)
    if into == "{channels}"
        into = bindings[:channel]
    end
    into
end

descended(bindings::Dict{Symbol, Any}, segment) = merge(
    bindings,
    Dict(:channel => "$(bindings[:channel])-$segment"),
)

evaluate_bindings(f!::Schedule{Scope}) = merge(
    # from outer scope:
    if f!.specification.barrier
        # Implicitly retain seed and output control, even if this scope has
        # a barrier (because its step is a Load); these are always available
        # in the loaded specification.
        Dict{Symbol, Any}(
            :seed => f!.bindings[:seed],
            :into => f!.bindings[:into],
            :channel => f!.bindings[:channel],
        )
    else
        f!.bindings
    end,

    # evaluated definitions:
    Dict{Symbol, Any}(
        name => evaluate(specification; f!.bindings)
        for (name, specification) in f!.specification.definitions
    ),

    # evaluated definitions' paths
    Dict{Symbol, Any}(
        Symbol("^$name") => Locator(f!.path)
        for name in keys(f!.specification.definitions)
    )
)

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

item(x; i, inject = nothing, as = Symbol(), bindings, path) = model(
    x,
    bindings = as == Symbol() ? bindings : merge(
        descended(bindings, i),
        Dict(as => evaluate(inject; bindings)),
    ),
    branch = false,
    path = "$path$i",
)

models(list::List; bindings, path) = (
    item(specification; i, bindings = descended(bindings, i), path)
    for (i, specification) in enumerate(list.items)
)

models(each::Each; bindings, path) = (
    item(each.step; i, inject = x, each.as, bindings, path)
    for (i, x) in enumerate(evaluate(each.items; bindings))
)

load_schedule(f!::Schedule{Load}; load) = Schedule(
    specification = Specification(
        load(f!.specification.path),
        bound = Set(keys(f!.bindings)),
    );
    f!.bindings,
    f!.branch,
    f!.path,
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
    f!.branch && error("cannot branch here: not a Sequence")

    @logmsg Progress :preparing at = f!.path
    x = Models.adapt(x, f!)  # potentially unwrap Branched
    bindings = evaluate_bindings(f!)
    path = "$(f!.path)$(f!.specification.branch ? '/' : '+')"
    step! = model(
        f!.specification.step;
        bindings,
        f!.specification.branch,
        path,
    )

    if haskey(bindings, :to) && bindings[Symbol("^to")].path == f!.path
        Δt = min(Δt, bindings[:to])
        @logmsg Progress :repeating at = f!.path todo = Δt
        done = 0.0
        while 0.0 < Δt
            current = Models.t(x)
            x = step!(x, Δt; context..., path)
            advance = Models.t(x) - current
            0.0 < advance || error("cannot progress")
            Δt -= advance
            done += advance
            @logmsg Progress :repeating at = f!.path done
        end
    else
        @logmsg Progress :descending at = f!.path
        x = step!(x, Δt; context..., path)
    end

    @logmsg Progress :done at = f!.path

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

(f!::Schedule{Load})(x, Δt::Float64; load, context...) =
    load_schedule(f!; load)(x, Δt; load, context..., f!.path)

reify(x, path::AbstractString; load = nothing) =
    isempty(path) ? x : error("cannot descend to '$path' in $(typeof(x))")

reify(x::AbstractDict{Symbol}, path::AbstractString; load = nothing) =
    isempty(path) ? x : Specifications.pluck(x, split(path, '.'))

reify(f!::Schedule{Template}, path::AbstractString; load) = reify(
    model(
        evaluate(f!.specification; f!.bindings);
        f!.bindings,
        f!.branch,
        path,
    ),
    path;
    load
)

function reify(f!::Schedule{Scope}, path::AbstractString; load)
    isempty(path) && return f!
    token = path[1]
    tail = path[2:end]
    bindings = evaluate_bindings(f!)
    if token == '.'
        reify(bindings, tail)
    elseif token == '+' || token == '/'
        step! = model(
            f!.specification.step;
            bindings,
            f!.specification.branch,
            path = "$(f!.path)$token",
        )
        reify(step!, tail; load)
    else
        error("cannot descend to '$path' in Scope at '$(f!.path)'")
    end
end

function reify(f!::Schedule{<:Sequence}, path::AbstractString; load)
    isempty(path) && return f!
    m = match(r"^(-?)(\d+)(.*)", path)
    if m !== nothing
        prefix, head, tail = m
        reify(f!, prefix, parse(Int, head), tail; load)
    else
        error("cannot descend to '$path' in Sequence at '$(f!.path)'")
    end
end

function reify(
    f!::Schedule{List},
    prefix::AbstractString,
    i::Int,
    tail::AbstractString;
    load,
)
    step! = item(
        f!.specification.items[i];
        i,
        bindings = descended(f!.bindings, i),
        path = "$(f!.path)$prefix",
    )
    reify(step!, tail; load)
end

function reify(
    f!::Schedule{Each},
    prefix::AbstractString,
    i::Int,
    tail::AbstractString;
    load,
)
    each = f!.specification
    step! = item(
        each.step;
        i,
        inject = evaluate(each.items; f!.bindings)[i],
        each.as,
        f!.bindings,
        path = "$(f!.path)$prefix",
    )
    reify(step!, tail; load)
end

reify(f!::Schedule{Load}, path::AbstractString; load) =
    reify(load_schedule(f!; load), path; load)

function reify(primitive!::Primitive, path::AbstractString; load = nothing)
    isempty(path) && return primitive!
    token = path[1]
    tail = path[2:end]
    if token == '+'
        primitive!.f!
    elseif token == '.'
        reify(primitive!.bindings, tail)
    else
        error("cannot descend to '$path' in Primitive at '$(primitive!.path)'")
    end
end

end
