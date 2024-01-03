module V1

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
    k₊::Float64 = 0.0
    k₋::Float64 = 0.0
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

@kwdef struct Definition
    polymerases::Symbol = :polymerases
    ribosomes::Symbol = :ribosomes
    proteasomes::Symbol = :proteasomes
    genes::Vector{Gene}
    reactions::Vector{ReactionDefinition} = ReactionDefinition[]
end

cast(::Type{Vector{Gene}}, xs::AbstractVector; context) = [
    cast(Gene, merge(Dict(:name => i), x); context)
    for (i, x) in enumerate(xs)
]

function cast(::Type{Gene}, x::AbstractDict{Symbol}; context)
    Rates =
        if haskey(x[:base_rates], :splicing)
            EukaryoteBaseRates
        else
            ProkaryoteBaseRates
        end

    @invoke cast(
        Gene{Rates}::Type,
        # Ensure we descend on these, even if they are not in x, because we will
        # look up model-wide defaults further down:
        merge(
            Dict(:activation => empty(x), :repression => empty(x)),
            x
        )::AbstractDict{Symbol};
        context,
    )
end

cast(::Type{ReactionDefinition}, x::AbstractDict{Symbol}; context) =
    @invoke cast(
        ReactionDefinition::Type,
        if haskey(x, :rates)
            merge(x, Dict(zip((:k₊, :k₋), x[:rates])))
        elseif haskey(x, :rate)
            merge(x, Dict(:k₊ => x[:rate]))
        else
            error("missing rates in reaction specification")
        end::AbstractDict{Symbol};
        context
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

cast(::Type{<:Regulation}, x::AbstractDict{Symbol}, ::Val{:aggregate}; _...) =
    aggregation(Val(Symbol(x[:aggregate])), x)

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

Models.describe(definition::Definition) = Models.Network(
    label = "'regulation/v1' network with $(length(definition.genes)) nodes",
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
    definition::Gene{ProkaryoteBaseRates};
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
    definition::Gene{EukaryoteBaseRates};
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

species_reference(name::Symbol; t, genes_by_name) =
    if haskey(genes_by_name, name)
        genes_by_name[name].proteins
    else
        species_variable(name; t)
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
                hill2(species_reference(from; t, genes_by_name), 1.0, at, k)
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
                hill2(species_reference(from; t, genes_by_name), 1.0, at, k)
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
                    proteases = species_reference(from; t, genes_by_name)
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
        # Bidirectional pairs are broken up, and reactions are only included if
        # their rate is nonzero.
        [
            Reaction(
                k₊,
                species_reference.(keys(from.counts); t, genes_by_name),
                species_reference.(keys(to.counts); t, genes_by_name),
                collect(values(from.counts)),
                collect(values(to.counts)),
            )
            for (; from, k₊, to) in definition.reactions
            if k₊ > 0.0
        ]

        [
            Reaction(
                k₋,
                species_reference.(keys(to.counts); t, genes_by_name),
                species_reference.(keys(from.counts); t, genes_by_name),
                collect(values(to.counts)),
                collect(values(from.counts)),
            )
            for (; from, k₋, to) in definition.reactions
            if k₋ > 0.0
        ]
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

SciML.JumpModel{Definition}(specification::AbstractDict{Symbol}) =
    SciML.JumpModel{Definition}(
        cast(Definition, specification),
        method = Symbol(get(specification, :method, "default"))
    )

function SciML.JumpModel{Definition}(definition::Definition; method::Symbol)
    allequal(typeof.(definition.genes)) ||
        error("mixing eukaryotic and prokaryotic genes is forbidden")

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

    SciML.JumpModel{Definition}(;
        definition,
        system = convert(JumpSystem, reaction_system),
        method = pick_method(reaction_system; method)(),
        parameters = Tuple(
            getproperty(genes_by_name[g.name], kind) =>
                getfield(g.base_rates, kind)
            for g in definition.genes
            for kind in fieldnames(typeof(g.base_rates))
            if kind ∉ (:activation, :deactivation)
        ),
    )
end

Specifications.constructor(::Val{Symbol("regulation/v1")}) =
    SciML.JumpModel{Definition}

end
