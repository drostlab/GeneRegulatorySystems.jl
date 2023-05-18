module Vanilla

import ..Models

using LinearAlgebra

using AxisArrays
using Catalyst
using ComponentArrays
using JumpProcesses
using Kronecker
using ModelingToolkit
using StatsBase
import Symbolics

Base.@kwdef struct BaseRates
    activation::Float64
    deactivation::Float64
    trigger::Float64
    transcription::Float64
    splicing::Float64
    translation::Float64
    abortion::Float64
    premrna_decay::Float64
    mrna_decay::Float64
    protein_decay::Float64
end

Base.@kwdef struct DirectRegulator
    from::Symbol
    k::Float64
end

Base.@kwdef struct HillRegulator
    from::Symbol
    at::Float64
    k::Float64 = -1.0
end

abstract type Regulation end

Base.@kwdef struct Activation <: Regulation
    slots::Vector{HillRegulator} = []
    aggregate::Function = minimum
end
(activation::Activation)(xs; T) =
    isempty(activation.slots) ? one(T) : activation.aggregate(xs)

Base.@kwdef struct Repression <: Regulation
    slots::Vector{HillRegulator} = []
    aggregate::Function = minimum
end
(repression::Repression)(xs; T) =
    isempty(repression.slots) ? one(T) : repression.aggregate(xs)

Base.@kwdef struct Proteolysis <: Regulation
    slots::Vector{DirectRegulator} = []
end

Base.@kwdef struct Gene
    name::Symbol
    base_rates::BaseRates
    activation::Activation = Activation()
    repression::Repression = Repression()
    proteolysis::Proteolysis = Proteolysis()
end

Base.@kwdef struct Definition
    volume::Float64
    polymerases::Int
    ribosomes::Int
    proteasomes::Int
    genes::Vector{Gene}
end

coerce(T::Type, x::AbstractDict{Symbol}, ::Val{K}; context) where {K} =
    coerce(fieldtype(T, K), x[K]; context)
coerce(::Type{Symbol}, x; _...) = Symbol(x)
coerce(T::Type{<:Number}, x::Number; _...) = convert(T, x)
coerce(T::Type{<:Number}, x::AbstractString; _...) = parse(T, x)
coerce(::Type{Vector{T}}, xs::AbstractVector; context) where {T} =
    coerce.(T, xs; context)
coerce(T::Type, x::AbstractDict{Symbol}; context = x) = _coerce(T, x; context)
_coerce(T::Type, x::AbstractDict{Symbol}; context) = T(; (
    key => coerce(T, x, Val(key); context)
    for key in keys(x)
    if hasfield(T, key)
)...)

coerce(::Type{Vector{Gene}}, xs::AbstractVector; context) = [
    coerce(Gene, merge(Dict(:name => i), x); context)
    for (i, x) in enumerate(xs)
]
coerce(::Type{Gene}, x::AbstractDict{Symbol}; context) = _coerce(
    Gene,
    # Ensure we descend on these, even if they are not in x, because we will
    # look up model-wide defaults further down:
    merge(Dict(:activation => empty(x), :repression => empty(x)), x);
    context
)
coerce(T::Type{<:Regulation}, xs::AbstractVector; context) =
    coerce(T, Dict(:slots => xs); context)
coerce(::Type{Activation}, x::AbstractDict{Symbol}; context) =
    _coerce(Activation, merge(get(context, :activation, empty(x)), x); context)
coerce(::Type{Repression}, x::AbstractDict{Symbol}; context) =
    _coerce(Repression, merge(get(context, :repression, empty(x)), x); context)

coerce(
    ::Type{<:Regulation},
    x::AbstractDict{Symbol},
    ::Val{:aggregate};
    _...
) = aggregation(Val(Symbol(x[:aggregate])), x)

aggregation(::Val{:neutral}, _) = one ∘ typeof ∘ first
aggregation(::Val{:minimum}, _) = minimum
aggregation(::Val{:maximum}, _) = maximum
aggregation(::Val{:mean}, _) = mean
aggregation(::Val{:geometric_mean}, _) = geomean
aggregation(::Val{:complement_geometric_mean}, _) = xs -> geomean(1.0 .- xs)
aggregation(::Val{:harmonic_mean}, _) = harmmean
aggregation(k::Val{:generalized_mean}, x) =
    aggregation(k, coerce(Float64, get(x, :p, 0.0)))
aggregation(::Val{:generalized_mean}, p::Float64) =
    p == -Inf ? minimum :
    p == -1.0 ? harmmean :
    p == 0.0 ? geomean :
    p == 1.0 ? mean :
    p == Inf ? maximum :
    Base.Fix2(genmean, p)

const REACTION_KINDS = collect(fieldnames(BaseRates))
const SPECIES_KINDS = [:promoter, :elongations, :premrnas, :mrnas, :proteins]
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
    reaction_kinds = REACTION_KINDS,
    species_kinds = SPECIES_KINDS,
)

Base.@kwdef struct Model <: Models.GillespieModel
    definition::Definition

    genes_index =
        Dict(gene.name => i for (i, gene) in enumerate(definition.genes))

    reactions = KERNEL ⊗ I(length(definition.genes))

    base_rates_by_kind = NamedTuple(
        name => map(definition.genes) do gene
            getfield(gene.base_rates, name)
        end
        for name in fieldnames(BaseRates)
    )
end

Models.Model(::Val{Symbol("vanilla-simple")}, specification) =
    Model(definition = coerce(Definition, specification))

function concentration(count; volume)
    # @David: units?
    Nₐ = 6.02e23
    count / (volume * Nₐ * 1e-24)
end

function Models.prepare_initial(specification::AbstractDict{Symbol}, θ::Model)
    ComponentVector(; (
        kind => [
            get(
                get(specification, gene.name, Dict{Symbol, Any}()),
                kind,
                0
            )
            for gene in θ.definition.genes
        ]
        for kind in SPECIES_KINDS
    )...)
end

function Models.collect(transcript::NamedTuple, θ::Model)
    columns(xs) = (
        Symbol("$(θ.definition.genes[i].name).$kind") =>
            (row -> row[kind][i]).(xs)
        for kind in keys(first(xs))
        for i in eachindex(first(xs)[kind])
    )

    (;
        :t => transcript.ts,
        columns(transcript.states)...,
        columns(transcript.rates)...,
    )
end

function Models.initialize(initial, θ::Model)
    state = copy(initial)
    rates = ComponentVector(; (
        name => Array{Float64}(undef, length(θ.definition.genes))
        for name in REACTION_KINDS
    )...)

    state, rates
end

function Models.regulate!(rates, state, θ::Model)
    (; volume, polymerases, ribosomes, proteasomes, genes) = θ.definition

    # slot activity:
    σ(x) = 1.0 / (1.0 + exp(-x))
    occupancy(x; k, β) = σ(
        k * (β == -Inf ? Inf : log(concentration(x; volume)) - β)
    )

    # activation/deactivation tempering coefficients:
    p₊s = (
        gene.repression(
            (
                occupancy(state.proteins[θ.genes_index[from]]; k, β = log(at))
                for (; from, at, k) in gene.repression.slots
            );
            T = eltype(rates)
        )
        for gene in genes
    )
    p₋s = (
        gene.activation(
            (
                occupancy(state.proteins[θ.genes_index[from]]; k, β = log(at))
                for (; from, at, k) in gene.activation.slots
            );
            T = eltype(rates)
        )
        for gene in genes
    )
    γs = (
        sum(gene.proteolysis.slots, init = zero(eltype(rates))) do (; from, k)
            k * state.proteins[θ.genes_index[from]]
        end
        for gene in genes
    )

    xs = state
    hs = rates
    base = θ.base_rates_by_kind

    # rate updates:
    hs.activation .=
        (1 .- xs.promoter) .* base.activation .* p₊s .* polymerases
    hs.deactivation .= xs.promoter .* base.deactivation .* p₋s
    hs.trigger .= xs.promoter .* base.trigger
    hs.transcription .= xs.elongations .* base.transcription
    hs.splicing .= xs.premrnas .* base.splicing
    hs.translation .= xs.mrnas .* base.translation .* ribosomes
    hs.abortion .= xs.elongations .* base.abortion
    hs.premrna_decay .= xs.premrnas .* base.premrna_decay
    hs.mrna_decay .= xs.mrnas .* base.mrna_decay
    hs.protein_decay .=
        xs.proteins .* (base.protein_decay .* proteasomes .+ γs)
end

Models.apply!(state, i, θ::Model) =
    state .+= θ.reactions[i, :]

gene(name::Symbol; ribosomes, proteasomes) = @reaction_network $name begin
    trigger, promoter --> promoter + elongations
    transcription, elongations --> premrnas
    splicing, premrnas --> mrnas
    translation * $ribosomes, mrnas --> mrnas + proteins
    abortion, elongations --> 0
    premrna_decay, premrnas --> 0
    mrna_decay, mrnas --> 0
    protein_decay * $proteasomes, proteins --> 0
end

# issue: proteins = 0 AND repression/activation = 0 -> NaN
hill2(X, v, K, n) = v / (1.0 + ifelse(iszero(K), 0.0, K / X) ^ n)

function regulation(
    genes_by_name::Dict{Symbol,<:ModelingToolkit.AbstractSystem};
    definition::Definition,
)
    # NOTE: cannot use algebraic equations (x ~ y) because Catalyst cannot turn
    #   them into a JumpSystem; need to use Reactions with a symbolic rate law
    #   directly

    # TODO: remove `concentration` calculations, fold into
    #   `repression`/`activation` constants

    (; volume, polymerases) = definition

    activation_rate(target::Gene) = (
        (1 - genes_by_name[target.name].promoter)
        * target.base_rates.activation
        * polymerases
        * target.repression(
            (  # ^ arguments and value go towards 0 as repression increases
                hill2(concentration(genes_by_name[from].proteins; volume), 1.0, at, k)
                for (; from, k, at) in target.repression.slots
            );
            T = Num
        )
    )

    deactivation_rate(target::Gene) = (
        genes_by_name[target.name].promoter
        * target.base_rates.deactivation
        * target.activation(
            (  # ^ arguments and value go towards 0 as activation increases
                hill2(concentration(genes_by_name[from].proteins; volume), 1.0, at, k)
                for (; from, k, at) in target.activation.slots
            );
            T = Num
        )
    )

    # Regulation for the whole network: for each target...
    mapreduce(vcat, definition.genes) do target::Gene
        [
            # ...activation (by tempering promoter deactivation)
            Reaction(
                deactivation_rate(target),
                [genes_by_name[target.name].promoter],
                nothing,
                only_use_rate = true
            )

            # ...repression (by tempering promoter activation)
            Reaction(
                activation_rate(target),
                nothing,
                [genes_by_name[target.name].promoter],
                only_use_rate = true
            )

            # ...repression (by proteolysis)
            map(target.proteolysis.slots) do (; from, k)
                proteases = genes_by_name[from].proteins
                proteins = genes_by_name[target.name].proteins

                Reaction(k, [proteases, proteins], [proteases])
            end
        ]
    end
end

const JUMP_PROCESSES_METHODS = Dict(
    "Direct" => Direct,
    "SortingDirect" => SortingDirect,
    "RSSA" => RSSA,
    "RSSACR" => RSSACR,
    "default" => RSSACR,
)

function Models.Model(::Val{Symbol("vanilla-Catalyst")}, specification)
    definition = coerce(Definition, specification)

    @variables t
    @parameters ribosomes proteasomes
    genes_by_name = Dict(
        g.name => gene(
            g.name,
            ribosomes = ParentScope(ribosomes),
            proteasomes = ParentScope(proteasomes),
        )
        for g in definition.genes
    )
    @named reaction_system = ReactionSystem(
        regulation(genes_by_name; definition),
        t,
        systems = collect(values(genes_by_name)),
    )

    jump_system = convert(JumpSystem, reaction_system)

    Models.SciMLJumpModel(
        system = jump_system,
        method = JUMP_PROCESSES_METHODS[get(specification, :method, "default")](),
        parameters = (
            ribosomes => definition.ribosomes,
            proteasomes => definition.proteasomes,
            (
                getproperty(genes_by_name[g.name], kind) =>
                    getfield(g.base_rates, kind)
                for g in definition.genes
                for kind in fieldnames(BaseRates)
                if kind ∉ (:activation, :deactivation)
            )...
        ),
    )
end

Models.Model(::Val{:vanilla}, specification) =
    Models.Model(Symbol("vanilla-Catalyst"), specification)

end