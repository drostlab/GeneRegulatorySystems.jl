module SciML

import ....GeneRegulatorySystems
import ..Models: Models, Model, FlatState
import Catalyst
using ModelingToolkit: ModelingToolkitBase, SymbolicIndexingInterface
import JumpProcesses

import Random
using Logging: LogLevel, @logmsg

Progress = LogLevel(-2)

normalize_name(s) =
    Symbol(replace(String(SymbolicIndexingInterface.getname(s)), '₊' => '.'))

function Models.Reaction(reaction::Catalyst.Reaction)
    function reagents(species, stoichiometries)
        Models.Reagents(Dict(
            normalize_name(species) => Int(stoichiometry)
            for (species, stoichiometry) in zip(species, stoichiometries)
        ))
    end
    function reaction_name(properties)
        haskey(properties, :name) &&
            return Symbol("reaction.", properties[:name])

        kind = properties[:kind]
        owner = properties[:owner]
        kind === :proteolysis && return Symbol(owner, ".", kind, ".", properties[:from])

        Symbol(owner, ".", kind)
    end
    properties = Dict{Symbol, Any}(reaction.metadata)
    Models.Reaction(
        name = reaction_name(properties),
        from = reagents(reaction.substrates, reaction.substoich),
        to = reagents(reaction.products, reaction.prodstoich),
        k₊ = reaction.rate,
        k₋ = zero(reaction.rate),
        properties = properties
    )
end

function Models.describe(system::Catalyst.ReactionSystem)
    function merge_reactions(reactions)
        rxs = Models.Reaction[]
        groups = Dict{Symbol, Dict{Symbol, Models.Reaction}}()
        for r in reactions
            dir = get(r.properties, :direction, nothing)
            if isnothing(r.name) || isnothing(dir)
                push!(rxs, r)
            else
                directions = get!(groups, r.name) do
                    Dict{Symbol, Models.Reaction}()
                end
                directions[dir] = r
            end
        end
        for (name, directions) in groups
            forward = get(directions, :forward, nothing)
            reverse = get(directions, :reverse, nothing)
            base = something(forward, reverse)
            properties = copy(base.properties)
            delete!(properties, :direction)
            properties[:parameters] = merge(
                isnothing(forward) ? Dict{Symbol,Symbol}() :
                    get(forward.properties, :parameters, Dict{Symbol,Symbol}()),
                isnothing(reverse) ? Dict{Symbol,Symbol}() :
                    get(reverse.properties, :parameters, Dict{Symbol,Symbol}()),
            )
            push!(rxs, Models.Reaction(
                name=name,
                from=isnothing(forward) ? reverse.to : forward.from,
                to = isnothing(forward) ? reverse.from : forward.to,
                k₊ = isnothing(forward) ? zero(reverse.k₊) : forward.k₊,
                k₋ = isnothing(reverse) ? zero(forward.k₊) : reverse.k₊,
                properties=properties
            ))
        end
        rxs
    end
    Models.ReactionNetwork(reactions = merge_reactions(Models.Reaction.(Catalyst.reactions(system))))
end


@kwdef mutable struct TriggerProgress
    i::Int = 0
end

function (trigger::TriggerProgress)(_u, _t, _integrator)
    trigger.i += 1
    trigger.i % 100000 == 0
end

# Since SciMLBase.DiscreteCallback is immutable, but we want to adjust progress
# reporting after construction, we wrap the progress reporter (emit directly or
# call back) in a mutable affect! of type ReportProgress.

@kwdef mutable struct EmitProgress
    t0::Float64 = 0.0
end

(progress::EmitProgress)(integrator) = @logmsg(
    Progress,
    :advancing,
    at = "JumpModel",
    done = integrator.t - progress.t0,
)

@kwdef struct CallbackProgress
    callback
end

function (progress::CallbackProgress)(integrator)
    progress.callback(:advancing, done = integrator.t)
    JumpProcesses.u_modified!(integrator, false)
end

@kwdef mutable struct ReportProgress
    reporter::Union{EmitProgress, CallbackProgress} = EmitProgress()
end

function (progress::ReportProgress)(integrator)
    progress.reporter(integrator)
    JumpProcesses.u_modified!(integrator, false)
end

"""
    JumpState

Contains the prepared `JumpProcesses.SSAIntegrator` `integrator` to be advanced
by a `JumpModel`.

In JumpProcesses.jl, the problem and integrator objects are tightly coupled. The
current time, values, RNG instance and (potentially) the recorded trajectories
are all contained in the integrator, but many mutable properties are usually
aliased from the problem, so we would typically consider both to be state.

However, since `JumpProblem` construction is expensive, we instead instruct
the `integrator` to perform a copy of the `JumpProblem` before using any of its
resources. The copy will share only those objects which are not modified when
the integrator advances. We can thus treat the `JumpProblem` as immutable. This
is still faster than rebuilding the whole `JumpProblem`.

To be compatible with a `JumpModel` `f!`, the `integrator` must have been
constructed for the same `f!.system` (i.e., from its `f!.problem`). To check
whether this is actually the case, `JumpState` also contains a reference to the
corresponding `f!`.
"""
@kwdef struct JumpState
    f!::Model{JumpState}
    integrator::JumpProcesses.SSAIntegrator
end

Models.t(x::JumpState) = x.integrator.t
Models.counts(x::JumpState) = Dict(
    normalize_name(s) => x.integrator[s]
    for s in SymbolicIndexingInterface.variable_symbols(x.integrator)
)
Models.randomness(x::JumpState) = x.integrator.rng

function Models.empty_trajectory!(x::JumpState)
    empty!(x.integrator.sol.u)
    empty!(x.integrator.sol.t)
end

FlatState(x::JumpState) = FlatState(
    t = Models.t(x),
    counts = Models.counts(x),
    randomness = copy(Models.randomness(x)),
)

JumpProblem(; system, method, more...) =
    ModelingToolkitBase.JumpProblem(
        system,
        # We will initialize these directly on the integrator:
        [s => 0 for s in ModelingToolkitBase.unknowns(system)],
        (0.0, Inf),
        aggregator = method,
        # Weirdly, constructing a `JumpProblem` consumes entropy. But everything
        # derived from it is supposed to be evanescent, so here we assign it a
        # new (deterministically seeded) RNG and will take care to reseed it
        # before initializing any integrator. This allows us to treat the
        # `JumpProblem` as effectively immutable. The RNG still needs to be an
        # independent instance (instead of its default TaskLocalRNG) so that the
        # deepcopy at integrator initialization will likewise produce
        # independent instances, and further to prevent any pollution of the
        # task-global entropy pool.
        rng = Random.Xoshiro(),
        u0_eltype = Int;
        more...,
    )

include("sciml_hacks.jl")

"""
    JumpModel <: Model{JumpState}

Wraps a SciML JumpProblem. Gene regulation models in this package ultimately get
compiled to `JumpModel`s.

# Specification

In JSON, `JumpModel`s can only be defined indirectly, such as via
[`Models.V1`](@ref).

# Invocation

    (f!::JumpModel)(x::JumpState, Δt::Float64; record = false, _...)

Advance the simulation by applying the stochastic dynamics `f!` to `x` for `Δt`
time units, realizing a segment of the state trajectory.

`x` must be compatible with `f!`, that is, the `JumpProcesses.JumpProblem` (and
corresponding integrator) in `x` must be compatible with `f!.system`. This is
currently conservatively checked as `f! === x.f!`. If necessary, users can call
`adapt!(x, f!)` to convert `x` appropriately.

If `record === true`, `x.integrator` will record all jumps, otherwise the
trajectory will not be retained (and only the final state will be available).
Either way, the recorded trajectory will be initially cleared, so it needs to be
extracted before the next invocation of `f!`.

Unfortunately, JumpProcesses.jl always uses a dense trajectory encoding, so that
the recorded trajectory information is highly redundant and needs to be filtered
by `each_event` for output in sparse long format. 
"""
@kwdef struct JumpModel <: Model{JumpState}
    problem::JumpProcesses.JumpProblem
end

Models.describe(::SciML.JumpModel) = Models.Label("SciML JumpSystem")

function JumpState(x::FlatState; f!::JumpModel)
    problem = JumpProcesses.isolated_copy(f!.problem)
    # ^ The integrator below will alias components from problem; we copy it here
    # to ensure f!.problem is never mutated.

    integrator = JumpProcesses.init(
        problem,
        JumpProcesses.SSAStepper(),
        save_start = false,
        callback = JumpProcesses.DiscreteCallback(
            TriggerProgress(),
            ReportProgress(),
            save_positions = (false, false),
        ),
        rng = Models.randomness(x),
    )
    integrator.t = Models.t(x)
    for s in SymbolicIndexingInterface.variable_symbols(integrator)
        integrator[s] = get(x.counts, normalize_name(s), 0)
    end
    JumpProcesses.reset_aggregated_jumps!(integrator)

    JumpState(; f!, integrator)
end

Models.adapt!(x::FlatState, f!::JumpModel, ::Val{_Copy}) where {_Copy} =
    JumpState(x; f!)
Models.adapt!(x::JumpState, f!::JumpModel, ::Val{Copy}) where {Copy} =
    x.f! === f! && !Copy ? x : JumpState(FlatState(x); f!)

function Models.each_event(callback::Function, x::JumpState)
    solution = x.integrator.sol

    names = normalize_name.(
        SymbolicIndexingInterface.variable_symbols(solution)
    )
    # ^ We assume that this access is safe and the order agrees with the values
    # in x.integrator.sol.u because this is how SciMLBase constructs the Table
    # reinterpretation in Tables.rows(::AbstractTimeseriesSolution).
    # ^ TODO: Check if this is still the case for newer versions of SciML!

    isempty(solution.u) && return
    (t, previous), rest = Iterators.peel(zip(solution.t, solution.u))

    # We generate events for all variables at the beginning of the segment...
    for i in LinearIndices(previous)
        callback(t, names[i], previous[i])
    end

    # ...and only for changes at later timepoints.
    for (t, current) in rest
        for i in LinearIndices(current)
            if current[i] != previous[i]
                callback(t, names[i], current[i])
            end
        end
        previous = current
    end
end

function (f!::JumpModel)(
    x::JumpState,
    Δt::Float64;
    record = false,
    consolidated_progress = nothing,
    verbose = consolidated_progress === nothing,
    _...
)
    f! === x.f! || error("incompatible JumpState, must call adapt!(x, f!)")
    isfinite(Δt) || error("cannot do this forever")

    progress = x.integrator.opts.callback.discrete_callbacks[1].affect!
    if verbose
        progress.reporter.t0 = Models.t(x)
    else
        progress.reporter = CallbackProgress(consolidated_progress)
    end

    verbose && @logmsg Progress :advancing at = "JumpModel" todo = Δt
    x.integrator.save_everystep = record
    if record
        JumpProcesses.savevalues!(x.integrator, true)
        JumpProcesses.step!(x.integrator, Δt, true)
    else
        JumpProcesses.step!(x.integrator, Δt, true)
        JumpProcesses.savevalues!(x.integrator, true)
    end
    verbose && @logmsg Progress :done at = "JumpModel"

    x
end

end
