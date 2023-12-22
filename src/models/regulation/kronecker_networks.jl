module KroneckerNetworks

import ...Conversion: cast
using ...GeneRegulatorySystems: randomness, σ, logit
using ..Models: Models, SciML, Vanilla
import ..Specifications

using Random
using SparseArrays

using Distributions
using Kronecker
using Roots

struct Nonnegative{T <: UnivariateDistribution}
    inner::T
end

@kwdef struct BaseRatesTemplate
    activation::Nonnegative{UnivariateDistribution}
    deactivation::Nonnegative{UnivariateDistribution}
    trigger::Nonnegative{UnivariateDistribution}
    transcription::Nonnegative{UnivariateDistribution}
    splicing::Nonnegative{UnivariateDistribution}
    translation::Nonnegative{UnivariateDistribution}
    abortion::Nonnegative{UnivariateDistribution}
    premrna_decay::Nonnegative{UnivariateDistribution}
    mrna_decay::Nonnegative{UnivariateDistribution}
    protein_decay::Nonnegative{UnivariateDistribution}
end

abstract type NetworkTemplate end

@kwdef struct ActivationNetworkTemplate <: NetworkTemplate
    adjacency::AbstractMatrix
    at::Nonnegative{UnivariateDistribution}
    k::UnivariateDistribution = Dirac(-1.0)
    # TODO: Should we support aggregation here?
end

@kwdef struct RepressionNetworkTemplate <: NetworkTemplate
    adjacency::AbstractMatrix
    at::Nonnegative{UnivariateDistribution}
    k::UnivariateDistribution = Dirac(-1.0)
    # TODO: Should we support aggregation here?
end

@kwdef struct ProteolysisNetworkTemplate <: NetworkTemplate
    adjacency::AbstractMatrix
    k::Nonnegative{UnivariateDistribution}
end

@kwdef struct Template
    base_rates::BaseRatesTemplate
    activation::Union{Some{ActivationNetworkTemplate}, Nothing} = nothing
    repression::Union{Some{RepressionNetworkTemplate}, Nothing} = nothing
    proteolysis::Union{Some{ProteolysisNetworkTemplate}, Nothing} = nothing
    n::Int =
        first(size(@something(activation, repression, proteolysis).adjacency))
end

@kwdef struct Definition
    seed::String
    template::Template
end

function Models.describe(definition::Definition)
    n = definition.template.n
    if n ≤ 32
        Models.describe(rand(randomness(definition.seed), definition.template))
    else
        Models.LabelDescription("(large network with $n nodes omitted)")
    end
end

regulator(
    template::Union{ActivationNetworkTemplate, RepressionNetworkTemplate};
    from::Symbol,
    randomness::AbstractRNG,
) = Vanilla.HillRegulator(
    at = rand(randomness, template.at),
    k = rand(randomness, template.k);
    from
)

regulator(
    template::ProteolysisNetworkTemplate;
    from::Symbol,
    randomness::AbstractRNG,
) = Vanilla.DirectRegulator(k = rand(randomness, template.k); from)

regulation(
    ::ActivationNetworkTemplate;
    slots::Vector{Vanilla.HillRegulator},
) = Vanilla.Activation(aggregate = minimum; slots)

regulation(
    ::RepressionNetworkTemplate;
    slots::Vector{Vanilla.HillRegulator},
) = Vanilla.Repression(aggregate = minimum; slots)

regulation(
    ::ProteolysisNetworkTemplate;
    slots::Vector{Vanilla.DirectRegulator},
) = Vanilla.Proteolysis(; slots)

function regulations(template::NetworkTemplate; n, randomness::AbstractRNG)
    size(template.adjacency) == (n, n) ||
        error("invalid initiator: must have size ($n, $n)")
    isprob(template.adjacency) ||
        error("invalid initiator: must be probabilities")
    map(eachcol(template.adjacency)) do column
        slots = [
            regulator(template; from = Symbol(i), randomness)
            for (i, cell) in enumerate(column)
            if rand(randomness) < cell
        ]
        regulation(template; slots)
    end
end

adjacency(initiator::AbstractMatrix; k::Int) =
    k == 1 ? initiator : kronecker(initiator, k)
adjacency(factors::AbstractVector) =
    length(factors) == 1 ? first(factors) : kronecker(factors...)

adjusted(initiator::AbstractMatrix, α::Float64) = σ.(α .+ logit.(initiator))
function adjusted(initiator::AbstractMatrix; k::Int, 𝔼links::Float64)
    n = size(initiator)[1]
    equivalent = 𝔼links ^ (1 / k)
    0 < equivalent < n || error("impossible expected link number target")
    target = n * equivalent

    residual(α) = sum(adjusted(initiator, α)) - target
    α₀ = find_zero(residual, 0.0)

    adjusted(initiator, α₀)
end

factor(xs::AbstractVector) = vcat(adjoint.(xs)...)

cast(::Type{UnivariateDistribution}, x::Real; _...) = Dirac(x)

function cast(::Type{UnivariateDistribution}, xs::AbstractVector; _...)
    T = getfield(Distributions, Symbol(xs[1]))
    T <: UnivariateDistribution || error("not a UnivariateDistribution")
    T(xs[2:end]...)
end

function cast(::Type{Nonnegative{T}}, x; _...) where {T}
    result = cast(T, x)
    minimum(result) ≥ 0.0 ||
        error("distribution must have nonnegative support")
    Nonnegative{UnivariateDistribution}(result)
end

function cast(::Type{AbstractMatrix}, xs::AbstractVector; _...)
    factors = factor.(xs)
    result = adjacency(factors)
    issquare(result) || error("adjacency must be square")
    result
end

function cast(T::Type{AbstractMatrix}, x::AbstractDict{Symbol}; _...)
    initiator = factor(x[:initiator])
    issquare(initiator) || error("initiator must be square")
    k = x[:power]
    if haskey(x, :expected_links_per_gene)
        𝔼links = x[:expected_links_per_gene]
        initiator = adjusted(initiator; k, 𝔼links)
    end
    adjacency(initiator; k)
end

Base.rand(randomness::AbstractRNG, d::Nonnegative{<:UnivariateDistribution}) =
    rand(randomness, d.inner)

Base.rand(randomness::AbstractRNG, template::BaseRatesTemplate) =
    Vanilla.BaseRates(; (
        field => rand(randomness, getfield(template, field))
        for field in fieldnames(Vanilla.BaseRates)
    )...)

function Base.rand(randomness::AbstractRNG, template::Template)
    n = template.n

    activations =
        if isnothing(template.activation)
            fill(Vanilla.Activation(), n)
        else
            regulations(something(template.activation); n, randomness)
        end

    repressions =
        if isnothing(template.repression)
            fill(Vanilla.Repression(), n)
        else
            regulations(something(template.repression); n, randomness)
        end

    proteolyses =
        if isnothing(template.proteolysis)
            fill(Vanilla.Proteolysis(), n)
        else
            regulations(something(template.proteolysis); n, randomness)
        end

    Vanilla.Definition(;
        genes = [
            Vanilla.Gene(
                name = Symbol(i),
                base_rates = rand(randomness, template.base_rates);
                activation,
                repression,
                proteolysis,
            )
            for (i, activation, repression, proteolysis) in
                zip(1:n, activations, repressions, proteolyses)
        ],
    )
end

function SciML.JumpModel{Definition}(specification::AbstractDict{Symbol})
    definition = Definition(
        seed = specification[:seed],
        template = cast(Template, specification),
    )

    synthesized = rand(randomness(definition.seed), definition.template)
    method = Symbol(get(specification, :method, "default"))
    vanilla = SciML.JumpModel{Vanilla.Definition}(synthesized; method)

    SciML.JumpModel{Definition}(;
        definition,
        vanilla.system,
        vanilla.method,
        vanilla.parameters,
    )
end

Specifications.constructor(::Val{Symbol("regulation/kronecker")}) =
    SciML.JumpModel{Definition}

end
