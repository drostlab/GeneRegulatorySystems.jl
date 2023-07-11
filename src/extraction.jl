module Extraction

import ..Conversion: cast

using Base: @kwdef
using Random

using Distributions

const Counts = Dict{Symbol, Int}

abstract type Scheme end

Scheme(::Nothing) = Merge([])

Scheme(specification::AbstractDict{Symbol}) =
    if length(specification) == 1
        Scheme(only(specification))
    else
        Merge([Scheme(s) for s in specification])
    end
Scheme(specification::Pair{Symbol}) =
    Scheme(Val(specification.first), specification.second)
function Scheme(::Val{S}, specification) where {S}
    T = eval(S)
    T <: Scheme || error("unknown extraction scheme")
    cast(T, specification)
end

cast(::Type{Scheme}, specification::Dict{Symbol, Any}; _...) =
    Scheme(specification)

(scheme::Scheme)(xs::Counts; randomness::AbstractRNG) = error("unimplemented")
(scheme::Scheme)(xs; randomness::AbstractRNG) = scheme(
    Counts(zip(keys(xs), collect(Int, xs)));
    randomness
)

@kwdef struct ResampleEachBinomial <: Scheme
    p::Float64

    ResampleEachBinomial(p::Float64) =
        0.0 ≤ p ≤ 1.0 ? new(p) : error("invalid probability")
end

(scheme::ResampleEachBinomial)(xs::Counts; randomness::AbstractRNG) = Counts(
    kind => rand(randomness, Binomial(count, scheme.p))
    for (kind, count) in xs
)

@kwdef struct ResampleEachAccumulate <: Scheme
    ps::Vector{Float64}

    ResampleEachAccumulate(ps::Vector{Float64}) =
        isprobvec(ps) ? new(ps) : error("invalid probability vector")
end

(scheme::ResampleEachAccumulate)(xs::Counts; randomness::AbstractRNG) = Counts(
    kind => sum(
        enumerate(rand(randomness, Multinomial(count, scheme.ps)))
    ) do (i, count′)
        (i - 1) * count′
    end
    for (kind, count) in xs
)

@kwdef struct ResampleHypergeometric <: Scheme
    n::Int

    ResampleHypergeometric(n::Int) =
        n ≥ 0 ? new(n) : error("invalid sample size")
end

function (scheme::ResampleHypergeometric)(xs::Counts; randomness::AbstractRNG)
    reservoir = sum(values(xs))
    todo = scheme.n
    reservoir ≤ todo && return xs

    result = Counts()
    for (kind, x) in xs
        reservoir -= x
        x′ = rand(randomness, Hypergeometric(x, reservoir, todo))
        todo -= x′
        result[kind] = x′
    end

    result
end

@kwdef struct ResampleMultinomial <: Scheme
    n::Int

    ResampleMultinomial(n::Int) = n ≥ 0 ? new(n) : error("invalid sample size")
end

(scheme::ResampleMultinomial)(xs::Counts; randomness::AbstractRNG) =
    Counts(zip(
        keys(xs),
        rand(randomness, Multinomial(n, values(xs) ./ sum(values(xs)))),
    ))

@kwdef struct ResampleDirichletMultinomial <: Scheme
    n::Int

    ResampleDirichletMultinomial(n::Int) =
        n ≥ 0 ? new(n) : error("invalid sample size")
end

(scheme::ResampleDirichletMultinomial)(xs::Counts; randomness::AbstractRNG) =
    Counts(zip(
        keys(xs),
        rand(randomness, DirichletMultinomial(n, collect(values(xs)))),
    ))

@kwdef struct Filter <: Scheme
    kinds::Regex
end

cast(::Type{Filter}, s::AbstractString) = Filter(Regex(s))

(scheme::Filter)(xs::Counts; _...) = filter(pairs(xs)) do (key, _)
    match(scheme.kinds, String(key)) !== nothing
end |> Counts

@kwdef struct Merge <: Scheme
    schemes::Vector{Scheme}
end

cast(::Type{Merge}, xs::AbstractVector) = Merge(Scheme.(xs))

(scheme::Merge)(xs::Counts; randomness::AbstractRNG) =
    foldl(scheme.schemes, init = Counts()) do xs′, inner
        mergewith(+, xs′, inner(xs; randomness))
    end

@kwdef struct Steps <: Scheme
    steps::Vector{Scheme}
end

cast(::Type{Steps}, xs::AbstractVector) = Steps(Scheme.(xs))

(scheme::Steps)(xs::Counts; randomness::AbstractRNG) =
    foldl(scheme.steps, init = xs) do xs′, step
        step(xs′; randomness)
    end

@kwdef struct Repeat <: Scheme
    count::Int
    step::Scheme

    Repeat(count::Int, step::Scheme) =
        0 ≤ count ? new(count, step) : error("negative repeat count")
end

(scheme::Repeat)(xs::Counts; randomness::AbstractRNG) =
    foldl(1:scheme.count, init = xs) do xs′, _
        scheme.step(xs′; randomness)
    end

Scheme(::Val{Symbol("proteome-simple")}, specification) = Steps([
    Filter(r"\.proteins$"),
    ResampleEachBinomial(get(specification, :collect, 1.0)),
    ResampleHypergeometric(get(specification, :target, typemax(Int))),
])

Scheme(::Val{Symbol("transcriptome-simple")}, specification) = Steps([
    Filter(r"\.(pre)?mrnas$"),
    ResampleEachBinomial(get(specification, :collect, 1.0)),
    ResampleHypergeometric(get(specification, :target, typemax(Int))),
])

function Scheme(
    ::Val{Symbol("transcriptome-amplified")},
    specification::AbstractDict{Symbol}
)
    p₀ = get(specification, :collect, 1.0)
    0.0 ≤ p₀ ≤ 1.0 || error("invalid collect probability")

    cycles = get(specification, :cycles, 0)
    0 ≤ cycles || error("invalid cycle count")

    dropout = get(specification, :dropout, 0.0)
    efficiency = get(specification, :efficiency, 1.0)
    ps = [dropout, 1.0 - dropout - efficiency, efficiency]
    isprobvec(ps) || error("invalid amplification settings")

    target = get(specification, :target, typemax(Int))

    Steps([
        Filter(r"\.(pre)?mrnas$"),
        ResampleEachBinomial(p = p₀),
        Repeat(count = cycles, step = ResampleEachAccumulate(ps)),
        ResampleHypergeometric(n = target),
    ])
end

end
