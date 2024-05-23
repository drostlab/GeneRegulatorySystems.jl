module Sampling

import ...Conversion: cast
using ..Models: V1

using Distributions

using Random

struct Nonnegative{T <: UnivariateDistribution}
    inner::T
end

function cast(::Type{Nonnegative{T}}, x; _...) where {T}
    result = cast(T, x)
    minimum(result) ≥ 0.0 ||
        error("distribution must have nonnegative support")
    Nonnegative{T}(result)
end

cast(::Type{<:UnivariateDistribution}, x::Real; _...) = Dirac(x)

function cast(::Type{<:UnivariateDistribution}, xs::AbstractVector; _...)
    T = getfield(Distributions, Symbol(first(xs)))
    T <: UnivariateDistribution || error("not a UnivariateDistribution")
    T((identity.(x) for x in xs[2:end])...)
end

cast(::Type{MultivariateDistribution}, xs::AbstractVector; _...) =
    if !isempty(xs) && first(xs) isa AbstractString
        T = getfield(Distributions, Symbol(first(xs)))
        T <: MultivariateDistribution || error("not a MultivariateDistribtuion")
        T((identity.(x) for x in xs[2:end])...)
    else
        Product(Dirac.(xs))
    end

Base.rand(randomness::AbstractRNG, d::Nonnegative{<:UnivariateDistribution}) =
    rand(randomness, d.inner)

@kwdef struct BaseRatesTemplate
    activation::Nonnegative{UnivariateDistribution}
    deactivation::Nonnegative{UnivariateDistribution}
    trigger::Nonnegative{UnivariateDistribution}
    transcription::Nonnegative{UnivariateDistribution}
    processing::Nonnegative{UnivariateDistribution}
    translation::Nonnegative{UnivariateDistribution}
    abortion::Nonnegative{UnivariateDistribution}
    premrna_decay::Nonnegative{UnivariateDistribution}
    mrna_decay::Nonnegative{UnivariateDistribution}
    protein_decay::Nonnegative{UnivariateDistribution}
end

Base.rand(randomness::AbstractRNG, template::BaseRatesTemplate) =
    V1.EukaryoteBaseRates(; (
        field => rand(randomness, getfield(template, field))
        for field in fieldnames(V1.EukaryoteBaseRates)
    )...)

end
