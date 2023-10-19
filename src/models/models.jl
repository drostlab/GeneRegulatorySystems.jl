module Models

import ..Conversion: cast
import ..Specifications

using Base: @kwdef
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

_adapt(x, f!::Model, copy::Val) = adapt(x, f!, copy)
_adapt(x::Branched, ::Model{Branched}, ::Val{false}) = x
_adapt(x::Branched, f!::Model, ::Val{false}) = _adapt(x.stem, f!, Val(false))
_adapt(x::Branched, f!::Model, ::Val{true}) = _adapt(x.step, f!, Val(true))
_adapt(x::FlatState, ::Model{FlatState}, ::Val{false}) = x
_adapt(x::FlatState, ::Model{Any}, ::Val{false}) = x
_adapt(x::FlatState, f!::Model, ::Val{true}) =
    _adapt(FlatState(x), f!, Val(false))

function table(x::FlatState; sorted)
    ks = keys(x.counts)
    if sorted
        ks = sort!(collect(ks))
    end
    [(; x.t, (k => x.counts[k] for k in ks)...)]
end

table(x::Branched; sorted) = table(x.stem; sorted)

(f!::Model)(_x, _Δt::Float64; _...) = error("unimplemented")

abstract type Description end

struct EmptyDescription <: Description end

@kwdef struct Network <: Description
    species_kinds
    species_groups
    links
end

describe(f!::Model) = EmptyDescription()

include("plumbing.jl")
include("scheduling.jl")
include("resampling.jl")
include("sciml.jl")
include("regulation/vanilla.jl")
include("regulation/kronecker_networks.jl")
include("extraction.jl")

end