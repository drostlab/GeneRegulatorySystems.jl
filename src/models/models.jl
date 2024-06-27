module Models

import ..Specifications

using Random

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

cast(::Type{FlatState}, x::Branched) = cast(FlatState, x.stem)

t(x::FlatState) = x.t
t(x::Branched) = t(x.stem)

randomness(x::FlatState) = x.randomness
randomness(x::Branched) = randomness(x.stem)

abstract type Model{State} end
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
except for retaining the the same `randomness` instance.

This machinery is used by
[`Schedule`](@ref GeneRegulatorySystems.Models.Scheduling.Schedule), but may
also be called directly. When `adapt` is called for a state-model-pair that has
no concrete `adapt` method defined, it falls back to making a `FlatState` copy
of `x` and retrying with that. This means that typically,
defining a new model `M <: Model{State}` that uses a new kind of `State`, it is
necessary to also define at least
- `adapt(x::FlatState, f!::M, _copy::Val{false})` so that `M` accepts arbitrary
  states, and
- `FlatState(x::State)` to support implicitly copying the state when `copy` is
  set and also to allow the result to be adapted automatically to other models.
However, implementing `adapt` methods for more specific state-model-pairs may
allow for more efficient state conversion between model invocations, for example
because a copy isn't required or parts of another state type can be reused.
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

end