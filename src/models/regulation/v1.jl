module V1

import ...Conversion: cast
using ..Models: Models, SciML
import ...Specifications: Specifications, representation

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
    processing::Float64
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

@kwdef struct Gene{BaseRates}
    name::Symbol
    base_rates::BaseRates
    unique::Bool = true
    activation::Activation = Activation()
    repression::Repression = Repression()
    proteolysis::Proteolysis = Proteolysis()
end

Gene(gene::Gene{BaseRates}; name) where {BaseRates} =
    Gene{BaseRates}(;
        name,
        gene.base_rates,
        gene.activation,
        gene.repression,
        gene.proteolysis,
    )

@kwdef struct Definition
    polymerases::Symbol = :polymerases
    ribosomes::Symbol = :ribosomes
    proteasomes::Symbol = :proteasomes
    genes::Vector{Gene} = Gene[]
    reactions::Vector{Models.MassActionReaction} = Models.MassActionReaction[]
end

cast(::Type{Vector{Gene}}, xs::AbstractVector; context) = [
    cast(
        Gene,
        merge(Dict(:name => lpad(i, ndigits(length(xs)), '0')), x);
        context,
    )
    for (i, x) in enumerate(xs)
]

function cast(::Type{Gene}, x::AbstractDict{Symbol}; context)
    Rates =
        if haskey(x[:base_rates], :processing)
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

aggregation_name(::typeof(one ∘ typeof ∘ first)) = "neutral"
aggregation_name(::typeof(geomean)) = "geometric_mean"
aggregation_name(::typeof(harmmean)) = "harmonic_mean"
aggregation_name(f::Function) = nameof(f)

regulation_representation(slots, ::typeof(minimum)) = representation(slots)
regulation_representation(slots, aggregation::Function) = Dict(
    :slots => representation(slots),
    :aggregation => aggregation_name(aggregation),
)
regulation_representation(slots, ::Base.Fix2{typeof(genmean), P}) where {P} =
    Dict(
        :slots => representation(slots),
        :aggregation => "generalized_mean",
        :p => P,
    )

representation(x::ProkaryoteBaseRates) = representation(x, simple = true)
representation(x::EukaryoteBaseRates) = representation(x, simple = true)
representation(x::DirectRegulator) = representation(x, simple = true)
representation(x::HillRegulator) =
    representation(x, simple = true, omit_defaults = [:k => -1.0])
representation(x::Activation) = regulation_representation(x.slots, x.aggregate)
representation(x::Repression) = regulation_representation(x.slots, x.aggregate)
representation(x::Proteolysis) = representation(x.slots)
representation(x::Gene) = representation(
    x,
    simple = true,
    omit_defaults = [
        :name => "",
        :activation => [],
        :repression => [],
        :proteolysis => [],
        :unique => true,
    ],
)
representation(x::Definition) = Dict{Symbol, Any}(
    Symbol("{regulation/v1}") => representation(
        x,
        simple = true,
        omit_defaults = [
            :polymerases => "polymerases",
            :ribosomes => "ribosomes",
            :proteasomes => "proteasomes",
            :genes => [],
            :reactions => [],
        ],
    )
)

Models.describe(::ReactionSystem) = Models.Label("Catalyst ReactionSystem")

Models.describe(definition::Definition) = Models.Descriptions([
    Models.Label(
        "'regulation/v1' network with $(length(definition.genes)) genes"
    )
    Models.Network(
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
        end,
        aliases = Dict(
            Symbol("$(gene.name).proteins") => gene.name
            for gene in definition.genes
        ),
    )
    Models.MassActionNetwork(definition.reactions)
])

cascade(::Gene{ProkaryoteBaseRates}; polymerases, ribosomes, proteasomes) =
    @reaction_network begin
        trigger, active + $polymerases --> active + elongations
        transcription, elongations --> mrnas + $polymerases
        translation, mrnas + $ribosomes --> mrnas + proteins + $ribosomes
        abortion, elongations --> $polymerases
        mrna_decay, mrnas --> 0
        protein_decay, proteins + $proteasomes --> $proteasomes
    end

cascade(::Gene{EukaryoteBaseRates}; polymerases, ribosomes, proteasomes) =
    @reaction_network begin
        trigger, active + $polymerases --> active + elongations
        transcription, elongations --> premrnas + $polymerases
        processing, premrnas --> mrnas
        translation, mrnas + $ribosomes --> mrnas + proteins + $ribosomes
        abortion, elongations --> $polymerases
        premrna_decay, premrnas --> 0
        mrna_decay, mrnas --> 0
        protein_decay, proteins + $proteasomes --> $proteasomes
    end

function gene(definition::Gene; polymerases, ribosomes, proteasomes, t)
    name = definition.name
    result = @reaction_network $name

    more = cascade(definition; polymerases, ribosomes, proteasomes)
    merge!(result, more)
    merge!(result.var_to_name, more.var_to_name)
    # ^ This is necessary due to a bug in Catalyst, but is a no-op once that is
    # fixed upstream.

    definition.unique || addspecies!(result, only(@species inactive(t)))

    result
end

function species_variable(name::Symbol; t)
    # Replace only the last '.' in the name with the scope separator '₊'
    # because the gene names may contain dots while the kind names certainly do
    # not.
    name = Symbol(replace(String(name), r"\.(?=[^.]*$)" => '₊'))
    only(@species $name(t))
end

species_reference(name::Symbol; t, genes) =
    haskey(genes, name) ? genes[name].proteins : species_variable(name; t)

# Catalyst.hill returns NaN if either both X and K are 0, or if X is 0 and
# n < 0. Since X may become (and often initially is) 0, this restricts what both
# K (which here is the activation/repression half-activation concentration) and
# n may be specified as by the user. To allow both of these violations in the
# limit case, we define a slightly more flexible hill function. This definition
# would not work correctly if K were symbolic (because then
# iszero(K) === false), but in our case it isn't.
hill2(X, v, K, n) = v / (1.0 + ifelse(iszero(K), 0.0, K / X) ^ n)

function regulation(
    genes::Dict{Symbol,<:ModelingToolkit.AbstractSystem};
    definition::Definition,
    t::Num,
)
    inactive(target::Gene) =
        if target.unique
            1 - genes[target.name].active
        else
            genes[target.name].inactive
        end

    activation_rate(target::Gene) = (
        inactive(target)
        * target.base_rates.activation
        * target.repression(
            (  # ^ arguments and value go towards 0 as repression increases
                hill2(species_reference(from; t, genes), 1.0, at, k)
                for (; from, k, at) in target.repression.slots
            );
            T = Num
        )
    )

    deactivation_rate(target::Gene) = (
        genes[target.name].active
        * target.base_rates.deactivation
        * target.activation(
            (  # ^ arguments and value go towards 0 as activation increases
                hill2(species_reference(from; t, genes), 1.0, at, k)
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
                    [genes[target.name].active],
                    target.unique ? nothing : [genes[target.name].inactive],
                    only_use_rate = true
                )

                # ...repression (by tempering promoter activation)
                Reaction(
                    activation_rate(target),
                    target.unique ? nothing : [genes[target.name].inactive],
                    [genes[target.name].active],
                    only_use_rate = true
                )

                # ...repression (by proteolysis)
                map(target.proteolysis.slots) do (; from, k)
                    proteases = species_reference(from; t, genes)
                    proteins = genes[target.name].proteins

                    if from == target.name
                        # This is a loop in the proteolysis repression network
                        # and means that the protein decays without another
                        # protease.
                        Reaction(k, [proteins], [proteins], [2], [1])
                    else
                        Reaction(k, [proteases, proteins], [proteases])
                    end
                end
            ]
        end

        # Additionally, we add arbitrary mass-action reactions as specified.
        # Bidirectional pairs are broken up, and reactions are only included if
        # their rate is nonzero.
        [
            Reaction(
                k₊,
                species_reference.(keys(from.counts); t, genes),
                species_reference.(keys(to.counts); t, genes),
                collect(values(from.counts)),
                collect(values(to.counts)),
            )
            for (; from, k₊, to) in definition.reactions
            if k₊ > 0.0
        ]

        [
            Reaction(
                k₋,
                species_reference.(keys(to.counts); t, genes),
                species_reference.(keys(from.counts); t, genes),
                collect(values(to.counts)),
                collect(values(from.counts)),
            )
            for (; from, k₋, to) in definition.reactions
            if k₋ > 0.0
        ]
    ]
end

const JUMP_PROCESSES_METHODS = Dict(
    :Direct => Direct,
    :SortingDirect => SortingDirect,
    :RSSA => RSSA,
    :RSSACR => RSSACR,
)

pick_method(system; method) = get(JUMP_PROCESSES_METHODS, method) do
    if numspecies(system) < 100 && numreactions(system) < 1000
        SortingDirect
    else
        RSSACR
    end
end

build(specification::AbstractDict{Symbol}) = build(
    cast(Definition, specification),
    method = Symbol(get(specification, :method, "default"))
)

function build(definition::Definition; method::Symbol)
    allequal(typeof.(definition.genes)) ||
        error("mixing eukaryotic and prokaryotic genes is forbidden")

    @variables t
    polymerases = species_variable(definition.polymerases; t)
    ribosomes = species_variable(definition.ribosomes; t)
    proteasomes = species_variable(definition.proteasomes; t)

    genes = Dict(
        g.name => gene(
            g,
            polymerases = ParentScope(polymerases),
            ribosomes = ParentScope(ribosomes),
            proteasomes = ParentScope(proteasomes);
            t,
        )
        for g in definition.genes
    )
    @named reaction_system = ReactionSystem(
        regulation(genes; definition, t),
        t,
        systems = collect(values(genes)),
    )

    Models.Derived(;
        definition,
        model = Models.Derived(
            definition = reaction_system,
            model = SciML.JumpModel(
                system = convert(JumpSystem, reaction_system),
                method = pick_method(reaction_system; method)(),
                parameters = Tuple(
                    getproperty(genes[g.name], kind) =>
                        getfield(g.base_rates, kind)
                    for g in definition.genes
                    for kind in fieldnames(typeof(g.base_rates))
                    if kind ∉ (:activation, :deactivation)
                ),
            ),
        ),
    )
end

Specifications.constructor(::Val{Symbol("regulation/v1")}) = build

end
