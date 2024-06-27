module RandomDifferentiation

using ...GeneRegulatorySystems: randomness
using ..Models: Models, V1, Differentiation, KroneckerNetworks
using ..Sampling: Nonnegative, BaseRatesTemplate
import ..Specifications

using Random

using DataStructures: PriorityQueue, enqueue!, dequeue!
using Distributions

@kwdef struct DifferentiationTemplate
    ratios::MultivariateDistribution
    differentiator_base_rates::BaseRatesTemplate
    timer_base_rates::BaseRatesTemplate
    duration::Nonnegative{UnivariateDistribution}
    trigger::Symbol = :trigger
    trigger_deposit::Int = 0
    buffer::Vector{Float64} = Float64[]
    timer_deposit::Dict{Symbol, Int} = Dict{Symbol, Int}()
    buffer_deposit::Int = 0
end

@kwdef struct InterRegulationTemplate
    count::Nonnegative{DiscreteUnivariateDistribution} =
        Nonnegative{DiscreteUnivariateDistribution}(Dirac(0))
    at::Nonnegative{UnivariateDistribution} =
        Nonnegative{UnivariateDistribution}(Dirac(Inf))
    k::UnivariateDistribution = Dirac(-1.0)
end

@kwdef struct Template
    differentiation::DifferentiationTemplate
    peripheral::Union{Some{KroneckerNetworks.Template}, Nothing} = nothing
    activation::InterRegulationTemplate = InterRegulationTemplate()
    repression::InterRegulationTemplate = InterRegulationTemplate()
end

@kwdef struct Definition
    seed::String
    template::Template
end

Models.describe(definition::Definition) = Models.Label(" \
    'regulation/random-differentiation' definition \
    with seed '$(definition.seed)'\
")

@kwdef struct Node
    next::Union{Node, Float64}
    alternative::Union{Node, Float64}
end

assemble_differentiation(
    ratio::Float64;
    template,
    name,
    randomness::AbstractRNG
) = (;
    differentiation = V1.Gene(
        name = Symbol(name),
        base_rates = rand(randomness, template.differentiator_base_rates),
    ),
    ratio,
    differentiators = [Symbol(name)],
)

function assemble_differentiation(
    node::Node;
    template,
    name = "differentiator",
    trigger = nothing,  # We special-case the root node by providing trigger.
    randomness::AbstractRNG,
)
    next = assemble_differentiation(
        node.next,
        name = "$(name)0";
        template,
        randomness,
    )
    alternative = assemble_differentiation(
        node.alternative,
        name = "$(name)1";
        template,
        randomness,
    )
    ratio = next.ratio + alternative.ratio
    differentiator = @something(
        trigger,
        V1.Gene(
            name = Symbol(name),
            base_rates = rand(randomness, template.differentiator_base_rates),
        )
    )
    duration = rand(randomness, template.duration)
    timer = V1.Gene(
        name = Symbol(),
        base_rates = rand(randomness, template.timer_base_rates),
    )

    (;
        differentiation = Differentiation.Transient(
            ratio = next.ratio / ratio,
            next = next.differentiation,
            alternative = alternative.differentiation;
            differentiator,
            duration,
            timer,
            template.buffer,
            template.timer_deposit,
            template.buffer_deposit,
        ),
        ratio,
        differentiators = [
            trigger === nothing ? [differentiator.name] : Symbol[]
            next.differentiators
            alternative.differentiators
        ]
    )
end

build(specification::AbstractDict{Symbol}) = build(
    Definition(
        seed = specification[:seed],
        template = Specifications.cast(Template, specification),
    ),
    method = Symbol(get(specification, :method, "default")),
    randomness = randomness(specification[:seed]),
)

function build(definition::Definition; method::Symbol, randomness::AbstractRNG)
    template = definition.template

    # Determine target terminal state ratios:
    ratios = Float64.(rand(randomness, template.differentiation.ratios))
    isempty(ratios) && error("no terminal states defined")
    ratios ./= sum(ratios)

    # Assemble the states into a Huffman tree:
    queue = PriorityQueue()
    for ratio in ratios
        enqueue!(queue, Ref(nothing) => ratio)
    end
    while length(queue) > 1
        next, next_ratio = peek(queue)
        dequeue!(queue)
        alternative, alternative_ratio = peek(queue)
        dequeue!(queue)

        node = Node(
            next = something(next[], next_ratio),
            alternative = something(alternative[], alternative_ratio),
        )
        enqueue!(queue, Ref(node) => next_ratio + alternative_ratio)
    end
    root = dequeue!(queue)[]

    # Convert the tree to a Differentiation.Transient definition, collecting
    # the names of the created differeniators:
    (; differentiation, differentiators) = assemble_differentiation(
        root,
        template = template.differentiation;
        template.differentiation.trigger,
        randomness,
    )

    # Sample a peripheral (Kronecker-linked) network, and have its genes
    # regulated by differentiators chosen uniformly at random:
    peripheral =
        if template.peripheral !== nothing
            rand(randomness, something(template.peripheral))
        else
            V1.Definition()
        end
    for gene in peripheral.genes
        for _ in 1:rand(randomness, template.activation.count)
            push!(
                gene.activation.slots,
                V1.HillRegulator(
                    from = rand(randomness, differentiators),
                    at = rand(randomness, template.activation.at),
                    k = rand(randomness, template.activation.k),
                )
            )
        end
        for _ in 1:rand(randomness, template.repression.count)
            push!(
                gene.repression.slots,
                V1.HillRegulator(
                    from = rand(randomness, differentiators),
                    at = rand(randomness, template.repression.at),
                    k = rand(randomness, template.repression.k),
                )
            )
        end
    end

    deposit = Dict(
        template.differentiation.trigger =>
            template.differentiation.trigger_deposit
    )

    Models.Derived(
        model = Differentiation.build(
            Differentiation.Definition(
                meta = Dict{Symbol, Any}(:ratios => ratios);
                differentiation,
                peripheral,
                deposit,
            );
            method,
        );
        definition,
    )
end

Specifications.constructor(::Val{Symbol("regulation/random-differentiation")}) =
    build

end
