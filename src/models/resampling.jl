module Resampling

using ...Conversion: cast
using ..Models: Model, FlatState
import ..Specifications

using Base: @kwdef

using Distributions

@kwdef struct ResampleEachBinomial <: Model{FlatState}
    p::Float64

    ResampleEachBinomial(p::Float64) =
        0.0 ≤ p ≤ 1.0 ? new(p) : error("invalid probability")
end

Specifications.constructor(::Val{Symbol("resample-each-binomial")}) =
    ResampleEachBinomial

function (f!::ResampleEachBinomial)(x::FlatState, _Δt::Float64; _...)
    map!(values(x.counts)) do count
        rand(x.randomness, Binomial(count, f!.p))
    end
    x
end

@kwdef struct ResampleEachAccumulate <: Model{FlatState}
    ps::Vector{Float64}

    function ResampleEachAccumulate(ps::AbstractVector)
        ps = cast(Vector{Float64}, ps)
        isprobvec(ps) ? new(ps) : error("invalid probability vector")
    end
end

Specifications.constructor(::Val{Symbol("resample-each-accumulate")}) =
    ResampleEachAccumulate

function (f!::ResampleEachAccumulate)(x::FlatState, _Δt::Float64; _...)
    map!(values(x.counts)) do count
        sum(
            enumerate(rand(x.randomness, Multinomial(count, f!.ps)))
        ) do (i, count′)
            (i - 1) * count′
        end
    end
    x
end

@kwdef struct ResampleHypergeometric <: Model{FlatState}
    n::Int

    ResampleHypergeometric(n::Int) =
        n ≥ 0 ? new(n) : error("invalid sample size")
end

Specifications.constructor(::Val{Symbol("resample-hypergeometric")}) =
    ResampleHypergeometric

function (f!::ResampleHypergeometric)(x::FlatState, _Δt::Float64; _...)
    reservoir = sum(values(x.counts))
    todo = f!.n
    reservoir ≤ todo && return x

    map!(values(x.counts)) do count
        reservoir -= count
        count = rand(x.randomness, Hypergeometric(count, reservoir, todo))
        todo -= count
        count
    end

    x
end

@kwdef struct ResampleMultinomial <: Model{FlatState}
    n::Int

    ResampleMultinomial(n::Int) = n ≥ 0 ? new(n) : error("invalid sample size")
end

Specifications.constructor(::Val{Symbol("resample-multinomial")}) =
    ResampleMultinomial

function (f!::ResampleMultinomial)(x::FlatState, _Δt::Float64; _...)
    ps = values(x.counts) ./ sum(values(x.counts))
    counts = rand(x.randomness, Multinomial(f!.n, ps))
    for (kind, count) in zip(keys(x.counts), counts)
        x.counts[kind] = count
    end
    x
end

@kwdef struct ResampleDirichletMultinomial <: Model{FlatState}
    n::Int

    ResampleDirichletMultinomial(n::Int) =
        n ≥ 0 ? new(n) : error("invalid sample size")
end

Specifications.constructor(::Val{Symbol("resample-Dirichlet-multinomial")}) =
    ResampleDirichletMultinomial

function (f!::ResampleDirichletMultinomial)(x::FlatState, _Δt::Float64; _...)
    counts = rand(
        x.randomness,
        DirichletMultinomial(f!.n, collect(values(x.counts))),
    )
    for (kind, count) in zip(keys(x.counts), counts)
        x.counts[kind] = count
    end
    x
end

end
