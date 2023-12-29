module Vanilla

import ...Conversion: cast
using ..Models: Models, SciML
import ...Specifications

using Base: @invoke

using Catalyst
using JumpProcesses
using ModelingToolkit
using StatsBase

@kwdef struct ProkaryoteBaseRates
    activation::Float64
    deactivation::Float64
    trigger::Float64
    transcription::Float64
    translation::Float64
    abortion::Float64
    mrna_decay::Float64
    protein_decay::Float64
end

@kwdef struct EukaryoteBaseRates
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

struct Reagents
    counts::Dict{Symbol, Int}
end

@kwdef struct ReactionDefinition
    from::Reagents = Reagents(Dict{Symbol, Int}())
    to::Reagents = Reagents(Dict{Symbol, Int}())
    k::Float64
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

@kwdef struct Gene{BaseRates}
    name::Symbol
    base_rates::BaseRates
    activation::Activation = Activation()
    repression::Repression = Repression()
    proteolysis::Proteolysis = Proteolysis()
end

const ProkaryoteGene = Gene{ProkaryoteBaseRates}
const EukaryoteGene = Gene{EukaryoteBaseRates}

@kwdef struct Definition{G <: Gene}
    polymerases::Symbol = :polymerases
    ribosomes::Symbol = :ribosomes
    proteasomes::Symbol = :proteasomes
    genes::Vector{G}
    reactions::Vector{ReactionDefinition} = ReactionDefinition[]
end

cast(
    ::Type{Vector{G}},
    xs::AbstractVector;
    context,
) where {G <: Gene} = [
    cast(G, merge(Dict(:name => i), x); context)
    for (i, x) in enumerate(xs)
]

cast(
    ::Type{G},
    x::AbstractDict{Symbol};
    context,
) where {G <: Gene} = @invoke cast(
    G::Type,
    # Ensure we descend on these, even if they are not in x, because we will
    # look up model-wide defaults further down:
    merge(
        Dict(:activation => empty(x), :repression => empty(x)),
        x
    )::AbstractDict{Symbol};
    context,
)

cast(::Type{Reagents}, x::AbstractDict{Symbol}; _...) = Reagents(x)

function cast(::Type{Reagents}, xs::AbstractVector; _...)
    result = Dict{Symbol, Int}()

    for x in xs
        reagent = Symbol(x)
        result[reagent] = get(result, reagent, 0) + 1
    end

    Reagents(result)
end

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

species_kinds(::Definition{ProkaryoteGene}) =
    [:promoter, :elongations, :mrnas, :proteins]

species_kinds(::Definition{EukaryoteGene}) =
    [:promoter, :elongations, :premrnas, :mrnas, :proteins]

Models.describe(definition::Definition) = Models.Network(
    label =
        "'regulation/vanilla' network with $(length(definition.genes)) nodes",
    species_kinds = species_kinds(definition),
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

function gene(
    definition::ProkaryoteGene;
    polymerases,
    ribosomes,
    proteasomes,
)
    name = definition.name
    @reaction_network $name begin
        trigger, promoter + $polymerases --> promoter + elongations
        transcription, elongations --> mrnas + $polymerases
        translation, mrnas + $ribosomes --> mrnas + proteins + $ribosomes
        abortion, elongations --> $polymerases
        mrna_decay, mrnas --> 0
        protein_decay, proteins + $proteasomes --> $proteasomes
    end
end

function gene(
    definition::EukaryoteGene;
    polymerases,
    ribosomes,
    proteasomes,
)
    name = definition.name
    @reaction_network $name begin
        trigger, promoter + $polymerases --> promoter + elongations
        transcription, elongations --> premrnas + $polymerases
        splicing, premrnas --> mrnas
        translation, mrnas + $ribosomes --> mrnas + proteins + $ribosomes
        abortion, elongations --> $polymerases
        premrna_decay, premrnas --> 0
        mrna_decay, mrnas --> 0
        protein_decay, proteins + $proteasomes --> $proteasomes
    end
end

function species_variable(name::Symbol; t)
    # Replace only the last '.' in the name with the scope separator '₊'
    # because the gene names may contain dots while the kind names certainly do
    # not.
    name = Symbol(replace(String(name), r"\.(?=[^.]*$)" => '₊'))
    only(@species $name(t))
end

# issue: proteins = 0 AND repression/activation = 0 -> NaN
hill2(X, v, K, n) = v / (1.0 + ifelse(iszero(K), 0.0, K / X) ^ n)

function regulation(
    genes_by_name::Dict{Symbol,<:ModelingToolkit.AbstractSystem};
    definition::Definition,
    t::Num,
)
    # NOTE: cannot use algebraic equations (x ~ y) because Catalyst cannot turn
    #   them into a JumpSystem; need to use Reactions with a symbolic rate law
    #   directly

    activation_rate(target::Gene) = (
        (1 - genes_by_name[target.name].promoter)
        * target.base_rates.activation
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

    # Regulation for the whole network:
    [
        # For each gene...
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
                        # This is a loop in the proteolysis repression network
                        # and means that the protein decays without another
                        # protease.
                        Reaction(k, [proteins], [proteins], [2], [1])
                    else
                        Reaction(k, [proteases, proteins], [proteases])
                    end
                end
                # ^ Although this case could now be expressed with additional
                # reactions as defined below, we keep the mechanism working for
                # now because it is shorter to type and because it is used by
                # KroneckerNetworks and makes their construction simpler.
            ]
        end

        # Additionally, we add arbitrary mass-action reactions as specified.
        map(definition.reactions) do (; from, to, k)
            Reaction(
                k,
                species_variable.(keys(from.counts); t),
                species_variable.(keys(to.counts); t),
                collect(values(from.counts)),
                collect(values(to.counts)),
            )
        end
        # TODO ^ This seems to break for moderate stoichiometries (≥ ~12) and
        # I don't yet know why. Building the function for the corresponding
        # `Catalyst.jumpratelaw` and calling it with typical values returns
        # plausible results, but I suspect an overflow issue somewhere.
    ]
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

SciML.JumpModel{D}(
    specification::AbstractDict{Symbol}
) where {D <: Definition} =
    SciML.JumpModel{D}(
        cast(D, specification),
        method = Symbol(get(specification, :method, "default"))
    )

function SciML.JumpModel{D}(
    definition::D;
    method::Symbol,
) where {BaseRates, D <: Definition{Gene{BaseRates}}}
    @variables t
    polymerases = species_variable(definition.polymerases; t)
    ribosomes = species_variable(definition.ribosomes; t)
    proteasomes = species_variable(definition.proteasomes; t)

    genes_by_name = Dict(
        g.name => gene(
            g,
            polymerases = ParentScope(polymerases),
            ribosomes = ParentScope(ribosomes),
            proteasomes = ParentScope(proteasomes),
        )
        for g in definition.genes
    )
    @named reaction_system = ReactionSystem(
        regulation(genes_by_name; definition, t),
        t,
        systems = collect(values(genes_by_name)),
    )

    SciML.JumpModel{D}(;
        definition,
        system = convert(JumpSystem, reaction_system),
        method = pick_method(reaction_system; method)(),
        parameters = Tuple(
            getproperty(genes_by_name[g.name], kind) =>
                getfield(g.base_rates, kind)
            for g in definition.genes
            for kind in fieldnames(BaseRates)
            if kind ∉ (:activation, :deactivation)
        ),
    )
end

Specifications.constructor(::Val{Symbol("regulation/vanilla-prokaryote")}) =
    SciML.JumpModel{Definition{ProkaryoteGene}}

Specifications.constructor(::Val{Symbol("regulation/vanilla-eukaryote")}) =
    SciML.JumpModel{Definition{EukaryoteGene}}

Specifications.constructor(::Val{Symbol("regulation/vanilla")}) =
    SciML.JumpModel{Definition{EukaryoteGene}}

end
