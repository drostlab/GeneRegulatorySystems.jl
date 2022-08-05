module Vanilla

import ..Models

using LinearAlgebra

using AxisArrays
using ComponentArrays
using Kronecker
using Memoization
using Query
using StatsBase

Base.@kwdef struct Link
    from::Int
    to::Int
    k::Float64 = -1.0
    repression::Float64 = Inf
    activation::Float64 = Inf
end

Base.@kwdef struct BaseRates
    activation::Vector{Float64}
    deactivation::Vector{Float64}
    trigger::Vector{Float64}
    transcription::Vector{Float64}
    splicing::Vector{Float64}
    translation::Vector{Float64}
    abortion::Vector{Float64}
    premrna_decay::Vector{Float64}
    mrna_decay::Vector{Float64}
    protein_decay::Vector{Float64}
end

Base.@kwdef struct Parameters <: Models.Parameters
    volume::Float64
    genes::Int
    polymerases::Int
    ribosomes::Int
    proteasomes::Int
    links::Vector{Link}
    aggregations::Union{Vector{Function}, Nothing} = nothing
    rates::BaseRates
end

const AGGREGATIONS = Dict(
    "minimum" => minimum,
    "maximum" => maximum,
    "mean" => mean,
    "geometric_mean" => geomean,
    "harmonic_mean" => harmmean,
    "median" => median,
)

coerce(T::Type{<:Number}, x::Number) = convert(T, x)
coerce(T::Type{<:Number}, x::AbstractString) = parse(T, x)
coerce(T::Type{Union{S, Nothing}}, x) where {S} = coerce(S, x)
coerce(T::Type{Vector{S}}, x::AbstractVector) where {S} = coerce.(S, x)
coerce(T::Type{Function}, x::AbstractString) = AGGREGATIONS[x]
coerce(T, x::AbstractDict{Symbol}) = T(; (
    key => coerce(fieldtype(T, key), value)
    for (key, value) in x
    if hasfield(T, key)
)...)

Models.load(::Val{:VanillaModel}, specification) =
    coerce(Parameters, specification)

const KERNEL = AxisArray(
    [
         1  0  0  0  0  # activate promoter
        -1  0  0  0  0  # deactivate promoter
         0  1  0  0  0  # trigger transcription
         0 -1  1  0  0  # finish transcription
         0  0 -1  1  0  # splice
         0  0  0  0  1  # translate
         0 -1  0  0  0  # abort transcription
         0  0 -1  0  0  # degrade pre-mRNA
         0  0  0 -1  0  # degrade mRNA
         0  0  0  0 -1  # degrade protein
    ],
    reactions = [
        :activation,
        :deactivation,
        :trigger,
        :transcription,
        :splicing,
        :translation,
        :abortion,
        :premrna_decay,
        :mrna_decay,
        :protein_decay,
    ],
    species = [
        :promoters,
        :transcriptions,
        :premrnas,
        :mrnas,
        :proteins,
    ],
)

@memoize reactions(θ::Parameters) = KERNEL ⊗ I(θ.genes)

@memoize links(θ::Parameters) =
    θ.links |> @groupby(_.to) |> @map(key(_) => collect(_)) |> Dict

@memoize aggregations(θ::Parameters) =
    @something θ.aggregations fill(minimum, θ.genes)

function concentration(count; volume)
    # @David: units?
    Nₐ = 6.02e23
    count / (volume * Nₐ * 1e-24)
end

function Models.initialize(initial::AbstractDict{Symbol}, θ::Parameters)
    reaction_names, species_names = axisvalues(KERNEL)

    state = ComponentVector(; (
        name => let
            counts = get(initial, name) do
                fill(0, θ.genes)
            end
            length(counts) == θ.genes || throw("invalid initial state")
            counts
        end
        for name in species_names
    )...)

    rates = ComponentVector(; (
        name => Array{Float64}(undef, θ.genes)
        for name in reaction_names
    )...)

    state, rates
end

function Models.regulate!(rates, state, θ::Parameters)
    # slot activity:
    σ(x) = 1.0 / (1.0 + exp(-x))
    occupancy(x; k, β) = σ(
        k * (β == -Inf ? Inf : log(concentration(x; θ.volume)) - β)
    )

    # activation/deactivation tempering coefficients:
    p₊s = (
        if haskey(links(θ), to)
            aggregations(θ)[to](
                occupancy(state.proteins[from]; k, β = log(repression))
                for (; from, k, repression) in links(θ)[to]
            )
        else
            1.0
        end
        for to in eachindex(state.proteins)
    )
    p₋s = (
        if haskey(links(θ), to)
            aggregations(θ)[to](
                occupancy(state.proteins[from]; k, β = log(activation))
                for (; from, k, activation) in links(θ)[to]
            )
        else
            1.0
        end
        for to in eachindex(state.proteins)
    )

    xs = state
    hs = rates
    θₕ = θ.rates

    # rate updates:
    hs.activation .=
        (1 .- xs.promoters) .* θₕ.activation .* p₊s .* θ.polymerases
    hs.deactivation .= xs.promoters .* θₕ.deactivation .* p₋s
    hs.trigger .= xs.promoters .* θₕ.trigger
    hs.transcription .= xs.transcriptions .* θₕ.transcription
    hs.splicing .= xs.premrnas .* θₕ.splicing
    hs.translation .= xs.mrnas .* θₕ.translation .* θ.ribosomes
    hs.abortion .= xs.transcriptions .* θₕ.abortion
    hs.premrna_decay .= xs.premrnas .* θₕ.premrna_decay
    hs.mrna_decay .= xs.mrnas .* θₕ.mrna_decay
    hs.protein_decay .= xs.proteins .* θₕ.protein_decay .* θ.proteasomes
end

Models.apply!(state, i, θ::Parameters) =
    state .+= reactions(θ)[i, :]

end