module Vanilla

import ...Conversion: cast
using ..Models: Models, SciML
import ...Specifications

using Base: @invoke

using Catalyst
using JumpProcesses
using ModelingToolkit
using StatsBase

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
    polymerases::Float64
    ribosomes::Float64
    proteasomes::Float64
    # ^ Due to a bug in ModelingToolkit when using mixed-type parameter maps,
    # we have to temporarily define these as Float64; see ModelingToolkit.jl
    # issue #2366.
    genes::Vector{Gene}
end

cast(::Type{Vector{Gene}}, xs::AbstractVector; context) = [
    cast(Gene, merge(Dict(:name => i), x); context)
    for (i, x) in enumerate(xs)
]
cast(::Type{Gene}, x::AbstractDict{Symbol}; context) = @invoke cast(
    Gene::Type,
    # Ensure we descend on these, even if they are not in x, because we will
    # look up model-wide defaults further down:
    merge(
        Dict(:activation => empty(x), :repression => empty(x)),
        x
    )::AbstractDict{Symbol};
    context
)
cast(T::Type{<:Regulation}, xs::AbstractVector; context) =
    cast(T, Dict(:slots => xs); context)
cast(::Type{Activation}, x::AbstractDict{Symbol}; context) = @invoke cast(
    Activation::Type,
    merge(get(context, :activation, empty(x)), x)::AbstractDict{Symbol};
    context
)
cast(::Type{Repression}, x::AbstractDict{Symbol}; context) = @invoke cast(
    Repression::Type,
    merge(get(context, :repression, empty(x)), x)::AbstractDict{Symbol};
    context
)
cast(
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
    aggregation(k, cast(Float64, get(x, :p, 0.0)))
aggregation(::Val{:generalized_mean}, p::Float64) =
    p == -Inf ? minimum :
    p == -1.0 ? harmmean :
    p == 0.0 ? geomean :
    p == 1.0 ? mean :
    p == Inf ? maximum :
    Base.Fix2(genmean, p)

const REACTION_KINDS = collect(fieldnames(BaseRates))
const SPECIES_KINDS = [:promoter, :elongations, :premrnas, :mrnas, :proteins]

Models.describe(definition::Definition) = Models.Network(
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
                    # means that the protein decays without another protease.
                    Reaction(k, [proteins], [proteins], [2], [1])
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
)

pick_method(system; method) = get(JUMP_PROCESSES_METHODS, method) do
    if numspecies(system) < 100 && numreactions(system) < 1000
        SortingDirect
    else
        RSSACR
    end
end

SciML.JumpModel{Definition}(specification::AbstractDict{Symbol}) =
    SciML.JumpModel{Definition}(
        cast(Definition, specification),
        method = Symbol(get(specification, :method, "default"))
    )

function SciML.JumpModel{Definition}(
    definition::Definition;
    method::Symbol
)
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

    SciML.JumpModel{Definition}(;
        definition,
        system = convert(JumpSystem, reaction_system),
        method = pick_method(reaction_system; method)(),
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

Specifications.constructor(::Val{Symbol("regulation/vanilla")}) =
    SciML.JumpModel{Definition}

end
