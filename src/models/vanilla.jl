module Vanilla

using ...GeneRegulatorySystems: σ
using ..Models
import ..Models: coerce

using Base: @kwdef, @invoke
using LinearAlgebra

using AxisArrays
using Catalyst
using ComponentArrays
using JumpProcesses
using Kronecker
using ModelingToolkit
using StatsBase
import Symbolics

@kwdef struct BaseRates
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

@kwdef struct DirectRegulator
    from::Symbol
    k::Float64
end

@kwdef struct HillRegulator
    from::Symbol
    at::Float64
    k::Float64 = -1.0
end

abstract type Regulation end

@kwdef struct Activation <: Regulation
    slots::Vector{HillRegulator} = []
    aggregate::Function = minimum
end
(activation::Activation)(xs; T) =
    isempty(activation.slots) ? one(T) : activation.aggregate(xs)

@kwdef struct Repression <: Regulation
    slots::Vector{HillRegulator} = []
    aggregate::Function = minimum
end
(repression::Repression)(xs; T) =
    isempty(repression.slots) ? one(T) : repression.aggregate(xs)

@kwdef struct Proteolysis <: Regulation
    slots::Vector{DirectRegulator} = []
end

@kwdef struct Gene
    name::Symbol
    base_rates::BaseRates
    activation::Activation = Activation()
    repression::Repression = Repression()
    proteolysis::Proteolysis = Proteolysis()
end

@kwdef struct Definition
    polymerases::Int
    ribosomes::Int
    proteasomes::Int
    genes::Vector{Gene}
end

coerce(::Type{Vector{Gene}}, xs::AbstractVector; context) = [
    coerce(Gene, merge(Dict(:name => i), x); context)
    for (i, x) in enumerate(xs)
]
coerce(::Type{Gene}, x::AbstractDict{Symbol}; context) = @invoke coerce(
    Gene::Type,
    # Ensure we descend on these, even if they are not in x, because we will
    # look up model-wide defaults further down:
    merge(
        Dict(:activation => empty(x), :repression => empty(x)),
        x
    )::AbstractDict{Symbol};
    context
)
coerce(T::Type{<:Regulation}, xs::AbstractVector; context) =
    coerce(T, Dict(:slots => xs); context)
coerce(::Type{Activation}, x::AbstractDict{Symbol}; context) = @invoke coerce(
    Activation::Type,
    merge(get(context, :activation, empty(x)), x)::AbstractDict{Symbol};
    context
)
coerce(::Type{Repression}, x::AbstractDict{Symbol}; context) = @invoke coerce(
    Repression::Type,
    merge(get(context, :repression, empty(x)), x)::AbstractDict{Symbol};
    context
)
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

@kwdef struct Model <: Models.GillespieModel
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

Models.describe(definition::Definition) = Models.ModelDescription(
    species_kinds = SPECIES_KINDS,
    species_groups = [gene.name for gene in definition.genes],
    links = mapreduce(vcat, definition.genes) do gene
        vcat(
            map(gene.activation.slots) do (; from, at, k)
                properties = Dict(:at => at, :k => k)
                (; to = gene.name, from, kind = :activation, properties)
            end,
            map(gene.repression.slots) do (; from, at, k)
                properties = Dict(:at => at, :k => k)
                (; to = gene.name, from, kind = :repression, properties)
            end,
            map(gene.proteolysis.slots) do (; from, k)
                properties = Dict(:k => k)
                (; to = gene.name, from, kind = :proteolysis, properties)
            end,
        )
    end
)
Models.describe(θ::Model) = Models.describe(θ.definition)

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
    (; polymerases, ribosomes, proteasomes, genes) = θ.definition

    # slot activity:
    occupancy(x; k, β) = σ(
        k * (β == -Inf ? Inf : log(x) - β)
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

    activation_rate(target::Gene) = (
        (1 - genes_by_name[target.name].promoter)
        * target.base_rates.activation
        * definition.polymerases
        * target.repression(
            (  # ^ arguments and value go towards 0 as repression increases
                hill2(genes_by_name[from].proteins, 1.0, at, k)
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
                hill2(genes_by_name[from].proteins, 1.0, at, k)
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

                if from == target.name
                    # This is a loop in the proteolysis repression network and
                    # means that the protein decays without proteosomes.
                    # (Perhaps this should be "2 proteins -> proteins", in
                    # which case we also need to update the naive Gillespie
                    # sampler above to reflect the combinatoric rate law.)
                    # TODO: Check if this makes sense and can actually happen.
                    Reaction(k, [proteins], nothing)
                else
                    Reaction(k, [proteases, proteins], [proteases])
                end
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

Models.Model(::Val{:vanilla}, specification) =
    Models.Model(Symbol("vanilla-Catalyst"), specification)

Models.Model(kind::Val{Symbol("vanilla-Catalyst")}, specification) =
    Models.SciMLJumpModel(
        coerce(Definition, specification),
        method = get(specification, :method, "default"),
    )

function Models.SciMLJumpModel(definition::Definition; method)
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
        method = JUMP_PROCESSES_METHODS[method](),
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
        description = Models.describe(definition),
    )
end

end
