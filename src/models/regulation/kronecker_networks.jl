module KroneckerNetworks

using ...GeneRegulatorySystems: randomness, σ, logit
using ..Models: Models, V1
using ..Sampling: Nonnegative, BaseRatesTemplate
import ..Specifications

using Random
using SparseArrays

using Distributions
using Kronecker
using Roots

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
    count::Int =
        first(size(@something(activation, repression, proteolysis).adjacency))
    prefix::String = ""
end

@kwdef struct Definition
    seed::String
    template::Template
end

Models.describe(definition::Definition) = Models.Label("\
    'regulation/kronecker' definition with seed '$(definition.seed)' \
    and $(definition.template.count)² initiators\
")

gene_name(i; n, prefix) = Symbol("$prefix$(lpad(i, ndigits(n), '0'))")

regulator(
    template::Union{ActivationNetworkTemplate, RepressionNetworkTemplate};
    from::Symbol,
    randomness::AbstractRNG,
) = V1.HillRegulator(
    at = rand(randomness, template.at),
    k = rand(randomness, template.k);
    from
)

regulator(
    template::ProteolysisNetworkTemplate;
    from::Symbol,
    randomness::AbstractRNG,
) = V1.DirectRegulator(k = rand(randomness, template.k); from)

regulation(::ActivationNetworkTemplate; slots::Vector{V1.HillRegulator}) =
    V1.Activation(; slots)

regulation(::RepressionNetworkTemplate; slots::Vector{V1.HillRegulator}) =
    V1.Repression(; slots)

regulation(::ProteolysisNetworkTemplate; slots::Vector{V1.DirectRegulator}) =
    V1.Proteolysis(; slots)

function regulations(
    template::NetworkTemplate;
    n,
    prefix,
    randomness::AbstractRNG,
)
    size(template.adjacency) == (n, n) ||
        error("invalid initiator: must have size ($n, $n)")
    isprob(template.adjacency) ||
        error("invalid initiator: must be probabilities")
    map(eachcol(template.adjacency)) do column
        slots = [
            regulator(template; from = gene_name(i; n, prefix), randomness)
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

function Specifications.cast(::Type{AbstractMatrix}, xs::AbstractVector; _...)
    factors = factor.(xs)
    result = adjacency(factors)
    issquare(result) || error("adjacency must be square")
    result
end

function Specifications.cast(
    T::Type{AbstractMatrix},
    x::AbstractDict{Symbol};
    _...,
)
    initiator = factor(x[:initiator])
    issquare(initiator) || error("initiator must be square")
    k = x[:power]
    if haskey(x, :expected_links_per_gene)
        𝔼links = x[:expected_links_per_gene]
        initiator = adjusted(initiator; k, 𝔼links)
    end
    adjacency(initiator; k)
end

function Base.rand(randomness::AbstractRNG, template::Template)
    n = template.count
    prefix = template.prefix

    activations =
        if isnothing(template.activation)
            [V1.Activation() for _ in 1:n]
        else
            regulations(something(template.activation); n, prefix, randomness)
        end

    repressions =
        if isnothing(template.repression)
            [V1.Repression() for _ in 1:n]
        else
            regulations(something(template.repression); n, prefix, randomness)
        end

    proteolyses =
        if isnothing(template.proteolysis)
            [V1.Proteolysis() for _ in 1:n]
        else
            regulations(something(template.proteolysis); n, prefix, randomness)
        end

    V1.Definition(;
        genes = [
            V1.Gene(
                name = gene_name(i; n, prefix),
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

function build(specification::AbstractDict{Symbol})
    # Pick a specific model instance by fixing the randomness:
    definition = Definition(
        seed = specification[:seed],
        template = Specifications.cast(Template, specification),
    )

    # Deterministically fill in the template and create a concrete V1
    # regulation model from it:
    synthesized = rand(randomness(definition.seed), definition.template)
    method = Symbol(get(specification, :method, "default"))
    model = V1.build(synthesized; method)

    # Package them up together:
    Models.Derived(; definition, model)
end

Specifications.constructor(::Val{Symbol("regulation/kronecker")}) = build

end
