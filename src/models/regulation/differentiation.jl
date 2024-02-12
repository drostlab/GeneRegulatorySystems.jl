module Differentiation

import ...Conversion: cast
using ..Models: Models, SciML, V1, Plumbing
import ..Specifications

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
    differentiator_self_activation::Float64 = 2.0
    differentiator_mutual_proteolysis_around::Float64 = 0.0001
    differentiator_proteolysis::Float64 = 0.0001
end

@kwdef struct Definition
    trigger::Union{Symbol, Nothing}
    differentiation::Transient
    peripheral::V1.Definition
    deposit::Dict{Symbol, Int} = Dict{Symbol, Int}()
end

Models.describe(definition::Definition) =
    Models.describe(synthesize(definition).v1_definition)

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

cast(::Type{Definition}, x::AbstractDict{Symbol}, context = x) = Definition(
    trigger = get(x, :trigger, nothing),
    differentiation = cast(Transient, x[:differentiation]),
    peripheral = cast(V1.Definition, x),
)

timing_factor(duration::Float64) =
    if 600.0 ≤ duration ≤ 943200.0
        # duration is between 10 minutes and 26 hours
        9.251e-11 * (102542.4 / (95652.0 - duration) - 1.0) ^ -0.947867298578199
    else
        error(
            "duration is '$duration'," *
            " outside its allowed range of [600.0, 943200.0]"
        )
    end

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
        from = V1.Reagents(Dict(timer.name => 2))
        to = V1.Reagents(Dict(Symbol("$(timer.name)_buffer") => 1))
        push!(reactions, V1.ReactionDefinition(; from, to, k₊, k₋))
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
    clamp(-2.0078e-6 * log(1.0 / target - 1.0), -0.00001, 0.00001)

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
    let at = transient.timer_repression
        push!(
            timer.repression.slots,
            V1.HillRegulator(from = next.name; at),
        )
        push!(
            timer.repression.slots,
            V1.HillRegulator(from = alternative.name; at),
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

function synthesize(definition::Definition)
    # Shallow-copy genes, reactions and deposit:
    genes = Dict(gene.name => gene for gene in definition.peripheral.genes)
    reactions = copy(definition.peripheral.reactions)
    deposit = copy(definition.deposit)

    # Extend them according to the differentiation definition:
    root = definition.differentiation.differentiator
    trigger = root isa V1.Gene ? root.name : root
    descend!(definition.differentiation; trigger, genes, reactions, deposit)

    # Assemble the extended regulatory model, but also return the original
    # definition with the now populated deposit definition:
    (;
        v1_definition = V1.Definition(
            genes = collect(values(genes));
            definition.peripheral.polymerases,
            definition.peripheral.ribosomes,
            definition.peripheral.proteasomes,
            reactions,
        ),
        definition = Definition(;
            definition.trigger,
            definition.differentiation,
            definition.peripheral,
            deposit,
        ),
    )
end

function SciML.JumpModel{Definition}(specification::AbstractDict{Symbol})
    definition = cast(Definition, specification)

    # Compile a V1.Definition, but also replace the original
    # Differentiation.Definition by an extended variant defining which species
    # to deposit for the newly created timers when we later bootstrap their
    # states (if requested):
    (; v1_definition, definition) = synthesize(definition)
    v1 = SciML.JumpModel{V1.Definition}(
        v1_definition,
        method = Symbol(get(specification, :method, "default"))
    )

    # Repackage it with its Differentiation.Definition so we can later identify
    # it as created from a differentiation template:
    SciML.JumpModel{Definition}(;
        definition,
        v1.system,
        v1.method,
        v1.parameters,
    )
end

Specifications.constructor(::Val{Symbol("regulation/differentiation")}) =
    SciML.JumpModel{Definition}

bootstrap(model::SciML.JumpModel{Definition}) =
    Plumbing.setter(model.definition.deposit)

Specifications.constructor(::Val{Symbol("bootstrap/differentiation")}) =
    bootstrap

end
