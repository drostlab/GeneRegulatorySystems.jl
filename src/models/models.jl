module Models

using ..Specifications: Specifications, Specification, Template

import JSON

using Random

const DEFAULTS = "$(@__DIR__)/defaults.specification.json"

@kwdef mutable struct FlatState
    t::Float64 = 0.0
    counts::Dict{Symbol, Int} = Dict{Symbol, Int}()
    randomness::AbstractRNG = Random.Xoshiro()
end
FlatState(x::FlatState) = FlatState(
    counts = deepcopy(x.counts);
    x.t,
    x.randomness
)

struct Branched
    stem
    branches::Vector
end
Branched(x) = Branched(x, [])

"""
    t(x)

Access the current simulation time of state `x`.
"""
function t end
t(x::FlatState) = x.t
t(x::Branched) = t(x.stem)

"""
    randomness(x)

Access the random number generator instance of state `x`.
"""
function randomness end
randomness(x::FlatState) = x.randomness
randomness(x::Branched) = randomness(x.stem)

"""
    Model{State}

Abstract supertype of all models.

`Model`s are functors: subtypes `M <: Model{State}` must define a call overload
method `(::M)(x::State, Δt::Float64; arguments...)` that advances the
simulation. Subtypes indicate which `State` type they expect to receive, and
must accept at least such `x`.

If `State` is a newly defined type (that is, specific to `M` and e.g. not
[`FlatState`](@ref)), that also requires implementing at least the following
methods:
- [`each_event(callback::Function, x::State)`](@ref each_event) to invoke
  `callback(t::Float64, key::Symbol, value::Int)` once for each state change
  event captured in `x`. This provides a unified way to extract the trajectory
  in long format.
- [`t(x::State)`](@ref t) to access the current simulation time.
- [`randomness(x::State)`](@ref randomness) to access the contained random
  number generator.
- [`adapt(x::FlatState, f!::M, copy::Val)`](@ref adapt) to convert a `FlatState`
  to a `State` and return it. The result must alias `x.randomness`. If `copy` is
  `Val(true)`, the result must otherwise be an independent deep copy of `x`.
- [`FlatState(x::State)`](@ref FlatState) to allow `adapt` for subsequent models
  to fall back on converting to `FlatState` and retrying if there is no more
  specific `adapt` method defined.
However, implementing `adapt` methods for more specific state-model-pairs may
allow for more efficient state conversion between model invocations, for example
because a copy isn't required or parts of another state type can be reused.
`adapt` is used by
[`Schedule`](@ref GeneRegulatorySystems.Models.Scheduling.Schedule) to convert
between the various state representations required by its contained primitive
`Model`s, but it may also be called directly.

In addition, a `Specifications.constructor(::Val{<:Symbol})` method typically
needs to be defined to return a function that instantiates a new `M` instance
from its `JSON.parse`d specification. This allows `M` to be defined within JSON
schedules.

---
    (f!::Model)(x, Δt::Float64; arguments...) = error("unimplemented")

Advance the simulation state `x` by at most `Δt` time units according to the
dynamics defined by `f!`.

Subtypes `<: Model{State}` must define specialized methods for this function,
one for each type of `x` they support, but at least for `State`.

Methods must advance the simulation state and return it, and they may do so as
an arbitrary type. They may arbitrarily modify `x` in the process, and they may
return (i.e. alias) it. Methods may assume that `Δt ≥ 0.0` and may accept
additional keyword `arguments` to control their behavior.
"""
abstract type Model{State} end

Model(x; bindings = Dict{Symbol, Any}()) =
    Model(Specification(x; bound = Set(keys(bindings))); bindings)
Model(specification::Specification; bindings) =
    Scheduling.Schedule(; specification, bindings)
Model(template::Template; bindings) =
    Specifications.expand(template; bindings)::Model

(f!::Model)(_x, _Δt::Float64; _...) = error("unimplemented")

"""
    Instant{State} <: Model{State}

Abstract supertype of instant models that ignore their time budget parameter
(`Δt`) and never progress on the time axis.
"""
abstract type Instant{State} <: Model{State} end

@kwdef struct Derived{State} <: Model{State}
    definition
    model::Model{State}
end

(f!::Derived)(x, Δt::Float64; arguments...) = f!.model(x, Δt; arguments...)

unwrap(model) = model
unwrap(derived::Derived) = unwrap(derived.model)

"""
    adapt(x, f!; copy = false)

Convert the simulation state `x` to a type accepted by the model `f!`.

If `copy` is set, `x` is not modified and the return value independent of it,
except for retaining the the same `randomness` instance. Otherwise, `adapt` is
allowed to modify or alias parts of `x`, which should therefore no longer be
used.
"""
function adapt end
adapt(x, f!::Model; copy = false) = _adapt(x, f!, Val(copy))
adapt(x, f!::Model, _copy) = _adapt(FlatState(x), f!, Val(false))
adapt(x, f!::Derived, copy) = _adapt(x, f!.model, copy)

_adapt(x, f!::Model, copy::Val) = adapt(x, f!, copy)
_adapt(x::Branched, ::Model{Branched}, ::Val{false}) = x
_adapt(x::Branched, f!::Model, copy::Val) = _adapt(x.stem, f!, copy)
_adapt(x::FlatState, ::Model{FlatState}, ::Val{false}) = x
_adapt(x::FlatState, ::Model{Any}, ::Val{false}) = x
_adapt(x::FlatState, f!::Model, ::Val{true}) = _adapt(
    FlatState(counts = deepcopy(x.counts); x.t, x.randomness),
    f!,
    Val(false)
)

each_event(callback::Function, x::FlatState) =
    for (key, value) in x.counts
        callback(x.t, key, value)
    end

each_event(callback::Function, x::Branched) = each_event(callback, x.stem)

@kwdef struct Reagents
    counts::Dict{Symbol, Int} = Dict{Symbol, Int}()
end

@kwdef struct MassActionReaction
    from::Reagents = Reagents()
    to::Reagents = Reagents()
    k₊::Float64 = 0.0
    k₋::Float64 = 0.0
end

Specifications.cast(
    ::Type{MassActionReaction},
    x::AbstractDict{Symbol};
    context,
) = @invoke Specifications.cast(
    MassActionReaction::Type,
    if haskey(x, :rates)
        merge(x, Dict(zip((:k₊, :k₋), x[:rates])))
    elseif haskey(x, :rate)
        merge(x, Dict(:k₊ => x[:rate]))
    else
        error("missing rates in reaction specification")
    end::AbstractDict{Symbol};
    context,
)

Specifications.cast(::Type{Reagents}, x::AbstractDict{Symbol}; _...) =
    Reagents(x)

function Specifications.cast(::Type{Reagents}, xs::AbstractVector; _...)
    result = Reagents()

    for x in xs
        reagent = Symbol(x)
        result.counts[reagent] = get(result.counts, reagent, 0) + 1
    end

    result
end

Specifications.representation(x::Reagents) = x.counts
Specifications.representation(x::MassActionReaction) = Dict{Symbol, Any}(
    :from => Specifications.representation(x.from),
    :to => Specifications.representation(x.to),
    :rates => [x.k₊, x.k₋]
)

abstract type Description end

struct EmptyDescription <: Description end

struct Descriptions <: Description
    descriptions::Vector{Description}
end

@kwdef struct Provenance <: Description
    source::Description
    description::Description
end

@kwdef struct Label <: Description
    label::String = ""
end

@kwdef struct Network <: Description
    species_groups::Vector{Symbol}
    links
    aliases::Dict{Symbol, Symbol} = Dict{Symbol, Symbol}()
end

@kwdef struct MassActionNetwork <: Description
    reactions::Vector{MassActionReaction} = MassActionReaction[]
end

describe(::Any) = EmptyDescription()
describe(derived::Derived) = Provenance(
    source = describe(derived.definition),
    description = describe(derived.model),
)

load_defaults() = JSON.parsefile(DEFAULTS, dicttype = Dict{Symbol, Any})

include("plumbing.jl")
include("scheduling.jl")
include("resampling.jl")
include("sciml.jl")
include("regulation/v1.jl")
include("regulation/differentiation.jl")
include("regulation/sampling.jl")
include("regulation/kronecker_networks.jl")
include("regulation/random_differentiation.jl")
include("extraction.jl")

load(
    path::AbstractString;
    into = "",
    channel = "",
    defaults = load_defaults(),
    others...,
) = Model(
    JSON.parsefile(path, dicttype = Dict{Symbol, Any}),
    bindings = (; into, channel, defaults, others...) |> pairs |> Dict
)

end
