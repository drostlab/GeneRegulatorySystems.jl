module Models

import ..Conversion: cast
import ..Specifications: Specifications, representation

using Random

@kwdef mutable struct FlatState
    t::Float64 = 0.0
    counts::Dict{Symbol, Int} = Dict{Symbol, Int}()
    randomness::AbstractRNG = Random.GLOBAL_RNG
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

abstract type Model{State} end
abstract type Instant{State} <: Model{State} end

@kwdef struct Derived{State} <: Model{State}
    definition
    model::Model{State}
end

unwrap(model) = model
unwrap(derived::Derived) = unwrap(derived.model)

adapt(x, f!::Model; copy = false) = _adapt(x, f!, Val(copy))
adapt(x, f!::Model, _copy) = _adapt(cast(FlatState, x), f!, Val(false))
adapt(x, f!::Derived, copy) = _adapt(x, f!.model, copy)

_adapt(x, f!::Model, copy::Val) = adapt(x, f!, copy)
_adapt(x::Branched, ::Model{Branched}, ::Val{false}) = x
_adapt(x::Branched, f!::Model, copy::Val) = _adapt(x.stem, f!, copy)
_adapt(x::FlatState, ::Model{FlatState}, ::Val{false}) = x
_adapt(x::FlatState, ::Model{Any}, ::Val{false}) = x
_adapt(x::FlatState, f!::Model, ::Val{true}) =
    _adapt(FlatState(x), f!, Val(false))

each_event(callback::Function, x::FlatState) =
    for (key, value) in x.counts
        callback(x.t, key, value)
    end

each_event(callback::Function, x::Branched) = each_event(callback, x.stem)

(f!::Model)(_x, _Δt::Float64; _...) = error("unimplemented")
(f!::Derived)(x, Δt::Float64; arguments...) = f!.model(x, Δt; arguments...)

@kwdef struct Reagents
    counts::Dict{Symbol, Int} = Dict{Symbol, Int}()
end

@kwdef struct MassActionReaction
    from::Reagents = Reagents()
    to::Reagents = Reagents()
    k₊::Float64 = 0.0
    k₋::Float64 = 0.0
end

cast(::Type{MassActionReaction}, x::AbstractDict{Symbol}; context) =
    @invoke cast(
        MassActionReaction::Type,
        if haskey(x, :rates)
            merge(x, Dict(zip((:k₊, :k₋), x[:rates])))
        elseif haskey(x, :rate)
            merge(x, Dict(:k₊ => x[:rate]))
        else
            error("missing rates in reaction specification")
        end::AbstractDict{Symbol};
        context
    )

cast(::Type{Reagents}, x::AbstractDict{Symbol}; _...) = Reagents(x)

function cast(::Type{Reagents}, xs::AbstractVector; _...)
    result = Reagents()

    for x in xs
        reagent = Symbol(x)
        result.counts[reagent] = get(result.counts, reagent, 0) + 1
    end

    result
end

representation(x::Reagents) = x.counts
representation(x::MassActionReaction) = Dict{Symbol, Any}(
    :from => representation(x.from),
    :to => representation(x.to),
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