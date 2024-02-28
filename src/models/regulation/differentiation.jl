module Differentiation

import ...Conversion: cast
using ..Models: Models, SciML, V1, Plumbing
import ..Specifications: Specifications, representation

@kwdef struct Transient
    differentiator::Union{V1.Gene, Symbol}
    duration::Float64
    timer::V1.Gene
    buffer::Vector{Float64} = Float64[]
    ratio::Float64 = 0.5
    next::Union{Transient, V1.Gene, Symbol}
    alternative::Union{Transient, V1.Gene, Symbol}

    # These values will be picked up when using the (optional) bootstrap
    # mechanism via the "{bootstrap/differentiation}" instant Model:
    timer_deposit::Dict{Symbol, Int} = Dict{Symbol, Int}()
    buffer_deposit::Int = 0

    # The following defaults can be overridden (e.g. in a specification), but
    # that may break the timing and ratio of differentiation, the calculations
    # of which currently assume these fixed values:
    timer_trigger_at::Float64 = 0.5
    timer_brake_at::Float64 = 0.5
    timer_repression::Float64 = 2.0
    timer_proteolysis::Float64 = 0.000002
    differentiator_self_activation::Float64 = 2.0
    differentiator_mutual_proteolysis_around::Float64 = 0.0001
    differentiator_proteolysis::Float64 = 0.0001
end

@kwdef struct Definition
    differentiation::Transient
    peripheral::V1.Definition
    deposit::Dict{Symbol, Int} = Dict{Symbol, Int}()
end

representation(x::Transient) = representation(
    x,
    simple = true,
    omit_defaults = [
        :buffer => []
        :timer_deposit => Dict()
        :buffer_deposit => 0
        :timer_trigger_at => 0.5
        :timer_brake_at => 0.5
        :timer_repression => 2.0
        :differentiator_self_activation => 2.0
        :differentiator_mutual_proteolysis_around => 0.0001
        :differentiator_proteolysis => 0.0001
    ]
)
representation(x::Definition) = Dict{Symbol, Any}(
    Symbol("{regulation/differentiation}") => merge(
        only(values(representation(x.peripheral))),
        Dict{Symbol, Any}(:differentiation => representation(x.differentiation))
    )
)

Models.describe(::Definition) =
    Models.Label("'regulation/differentiation' definition")

function cast(
    ::Type{Transient},
    x::AbstractDict{Symbol},
    ::Val{:differentiator};
    context,
)
    d = x[:differentiator]
    if d isa AbstractString
        Symbol(d)
    else
        cast(V1.Gene, merge(Dict(:name => ""), d); context)
    end
end

cast(::Type{Transient}, x::AbstractDict{Symbol}, ::Val{:timer}; context) =
    cast(V1.Gene, merge(Dict(:name => ""), x[:timer]); context)

cast(::Type{Union{Symbol, Transient, V1.Gene}}, x::AbstractString; _...) =
    Symbol(x)
cast(
    ::Type{Union{Symbol, Transient, V1.Gene}},
    x::AbstractDict{Symbol};
    context,
) =
    if haskey(x, :next)
        cast(Transient, x; context)
    else
        cast(V1.Gene, merge(Dict(:name => ""), x); context)
    end

cast(::Type{Definition}, x::AbstractDict{Symbol}; context = x) = Definition(
    differentiation = cast(Transient, x[:differentiation]; context),
    peripheral = cast(V1.Definition, x; context),
)

timing_factor(duration::Float64) =
    0.00001982551383307971 * max(600.0, duration)^-0.973

function make_timer!(
    gene::V1.Gene;
    default_name,
    duration,
    buffer_rates,
    genes,
    reactions,
)
    name = gene.name == Symbol() ? Symbol(default_name) : gene.name
    timing = timing_factor(duration)
    timer = V1.Gene(;
        name,
        base_rates = typeof(gene.base_rates)(;
            (
                name => getproperty(gene.base_rates, name)
                for name in propertynames(gene.base_rates)
            )...,
            transcription = timing * gene.base_rates.transcription,
            protein_decay = timing * gene.base_rates.protein_decay,
        ),
        activation = deepcopy(gene.activation),
        repression = deepcopy(gene.repression),
        proteolysis = deepcopy(gene.proteolysis),
    )

    # If specified, add a dimerization buffer reaction for the timer gene's
    # proteins.
    if !isempty(buffer_rates)
        if length(buffer_rates) == 1
            k₊ = k₋ = only(buffer_rates)
        elseif length(buffer_rates) == 2
            k₊, k₋ = buffer_rates
        else
            error("timer dimerization buffer reaction has too many rates")
        end
        from = Models.Reagents(Dict(timer.name => 2))
        to = Models.Reagents(Dict(Symbol("$(timer.name)_buffer") => 1))
        push!(reactions, Models.MassActionReaction(; from, to, k₊, k₋))
    end

    genes[timer.name] = timer

    timer
end

function obtain_differentiator!(gene::V1.Gene; default_name, genes)
    # register gene defined inline
    result =
        if gene.name == Symbol()
            V1.Gene(gene; name = Symbol(default_name))
        else
            gene
        end
    genes[result.name] = deepcopy(result)
end

function obtain_differentiator!(reference::Symbol; default_name, genes)
    # replace referenced gene with a copy
    result = pop!(genes, reference)
    genes[result.name] = deepcopy(result)
end

obtain_differentiator!(transient::Transient; default_name, genes) =
    obtain_differentiator!(transient.differentiator; default_name, genes)

proportion_adjustment(target::Float64) =
    clamp(2.0078e-6 * log(1.0 / target - 1.0), -0.00001, 0.00001)

descend!(::Any; _...) = nothing
function descend!(
    transient::Transient;
    trigger,
    brake = nothing,
    genes,
    reactions,
    deposit,
)
    # Obtain or create genes for timing and downstream differentiators:
    timer = make_timer!(
        transient.timer;
        default_name = "$(trigger)_timer",
        transient.duration,
        buffer_rates = transient.buffer,
        genes,
        reactions,
    )
    next = obtain_differentiator!(
        transient.next,
        default_name = "$(trigger)0";
        genes,
    )
    alternative = obtain_differentiator!(
        transient.alternative,
        default_name = "$(trigger)1";
        genes,
    )

    # Add regulation triggering timer decay:
    push!(
        timer.repression.slots,
        V1.HillRegulator(from = trigger, at = transient.timer_trigger_at)
    )

    # The alternative upstream differentiator prevents timer decay:
    brake === nothing || push!(
        timer.activation.slots,
        V1.HillRegulator(from = brake, at = transient.timer_brake_at)
    )

    # Control the switch proportion by tuning mutually repressive proteolysis
    # between the differentiators:
    let
        k = transient.differentiator_mutual_proteolysis_around
        δ = proportion_adjustment(transient.ratio)
        δ < k || error(
            "differentiator_mutual_proteolysis_around is too low for this" *
            " proportion adjustment"
        )
        push!(
            next.proteolysis.slots,
            V1.DirectRegulator(from = alternative.name, k = k + δ)
        )
        push!(
            alternative.proteolysis.slots,
            V1.DirectRegulator(from = next.name, k = k - δ)
        )
    end

    # Add self-activation for the differentiators:
    let at = transient.differentiator_self_activation
        push!(
            next.activation.slots,
            V1.HillRegulator(from = next.name; at)
        )
        push!(
            alternative.activation.slots,
            V1.HillRegulator(from = alternative.name; at)
        )
    end

    # Proteolytic repression from an undecayed timer prevents differentiation:
    let k = transient.differentiator_proteolysis
        push!(
            next.proteolysis.slots,
            V1.DirectRegulator(from = timer.name; k),
        )
        push!(
            alternative.proteolysis.slots,
            V1.DirectRegulator(from = timer.name; k),
        )
    end

    # Repression from any downstream differentiator keeps the timer depleted
    # in the differentiated state:
    let at = transient.timer_repression, k = transient.timer_proteolysis
        push!(
            timer.repression.slots,
            V1.HillRegulator(from = next.name; at),
        )
        push!(
            timer.repression.slots,
            V1.HillRegulator(from = alternative.name; at),
        )
        push!(
            timer.proteolysis.slots,
            V1.DirectRegulator(from = next.name; k),
        )
        push!(
            timer.proteolysis.slots,
            V1.DirectRegulator(from = alternative.name; k),
        )
    end

    # Extend the initial deposit to let the (optional) separate bootstrap stage
    # ("{boostrap/differentiation}" instant model) know what to initialize:
    for (kind, value) in transient.timer_deposit
        deposit[Symbol("$(timer.name).$kind")] = value
    end
    if !isempty(transient.buffer)
        deposit[Symbol("$(timer.name)_buffer")] = transient.buffer_deposit
    end

    # Recurse for any nested differentiations:
    descend!(
        transient.next,
        trigger = next.name,
        brake = alternative.name;
        genes,
        reactions,
        deposit,
    )
    descend!(
        transient.alternative,
        trigger = alternative.name,
        brake = next.name;
        genes,
        reactions,
        deposit,
    )
end

build(specification::AbstractDict{Symbol}) = build(
    cast(Definition, specification),
    method = Symbol(get(specification, :method, "default"))
)

function build(definition::Definition; method::Symbol)
    # Shallow-copy genes, reactions and deposit:
    genes = Dict(gene.name => gene for gene in definition.peripheral.genes)
    reactions = copy(definition.peripheral.reactions)
    deposit = copy(definition.deposit)

    # Extend them according to the differentiation definition:
    root = definition.differentiation.differentiator
    trigger =
        if root isa V1.Gene
            obtain_differentiator!(
                root,
                default_name = "differentiator";
                genes,
            ).name
        else
            # Exclusively for the root differentiator, we allow it to to alias
            # a non-gene species. (All consequent differentiators must be genes
            # because they will be transcriptionally regulated.)
            root
        end
    descend!(definition.differentiation; trigger, genes, reactions, deposit)

    # Compile down to a V1 model:
    model = V1.build(
        V1.Definition(
            genes = collect(values(genes));
            definition.peripheral.polymerases,
            definition.peripheral.ribosomes,
            definition.peripheral.proteasomes,
            reactions,
        );
        method,
    )

    # Replace the original Differentiation.Definition by an extended variant
    # defining which species to deposit for the newly created timers when we
    # later bootstrap their states (if requested):
    definition = Definition(;
        definition.differentiation,
        definition.peripheral,
        deposit,
    )

    Models.Derived(; definition, model)
end

Specifications.constructor(::Val{Symbol("regulation/differentiation")}) =
    build

bootstrap(model::Models.Derived) = bootstrap(model.definition, model.model)
bootstrap(d::Definition, _model::Models.Model) = Plumbing.setter(d.deposit)
bootstrap(_definition::Any, model::Models.Model) = bootstrap(model)

Specifications.constructor(::Val{Symbol("bootstrap/differentiation")}) =
    bootstrap

end
