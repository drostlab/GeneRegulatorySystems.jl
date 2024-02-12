module Models

import ..Conversion: cast
import ..Specifications

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

adapt(x, f!::Model; copy = false) = _adapt(x, f!, Val(copy))
adapt(x, f!::Model, _copy) = _adapt(cast(FlatState, x), f!, Val(false))

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

abstract type Description end

struct EmptyDescription <: Description end

struct LabelDescription <: Description
    label::String
end

@kwdef struct Network <: Description
    label::String = ""
    species_groups::Vector{Symbol}
    links
end

describe(::Model) = EmptyDescription()

include("plumbing.jl")
include("scheduling.jl")
include("resampling.jl")
include("sciml.jl")
include("regulation/v1.jl")
include("regulation/kronecker_networks.jl")
include("regulation/differentiation.jl")
include("extraction.jl")

end