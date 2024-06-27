module SciML

using ..Models: Models, Model, FlatState

import JumpProcesses
import ModelingToolkit

using Random
using Logging: LogLevel, @logmsg

Progress = LogLevel(-2)

normalize_name(s) =
    Symbol(replace(String(ModelingToolkit.getname(s)), '₊' => '.'))

@kwdef mutable struct TriggerProgress
    i::Int = 0
end

function (trigger::TriggerProgress)(_u, _t, _integrator)
    trigger.i += 1
    trigger.i % 10000 == 0
end

@kwdef mutable struct EmitProgress
    t0::Float64 = 0.0
end

(progress::EmitProgress)(integrator) = @logmsg(
    Progress,
    :stepping,
    at = "JumpModel",
    done = integrator.t - progress.t0,
)

@kwdef struct JumpState
    f!::Model{JumpState}
    problem::JumpProcesses.JumpProblem
    integrator::JumpProcesses.SSAIntegrator = ModelingToolkit.init(
        problem,
        JumpProcesses.SSAStepper(),
        save_start = false,
        callback = JumpProcesses.DiscreteCallback(
            TriggerProgress(),
            EmitProgress(),
            save_positions = (false, false),
        ),
    )
end

Models.t(x::JumpState) = x.integrator.t
Models.randomness(x::JumpState) = x.problem.rng

FlatState(x::JumpState) = FlatState(
    counts = Dict(
        normalize_name(s) => x.integrator[s]
        for s in ModelingToolkit.SymbolicIndexingInterface.variable_symbols(
            x.integrator
        )
    ),
    randomness = x.problem.rng;
    x.integrator.t,
)

@kwdef struct JumpModel <: Model{JumpState}
    system::ModelingToolkit.JumpSystem
    method::JumpProcesses.AbstractAggregatorAlgorithm
    parameters
end

Models.describe(::SciML.JumpModel) = Models.Label("SciML JumpSystem")

Models.adapt(x::JumpState, f!::JumpModel, ::Val{Copy}) where {Copy} =
    if x.f! === f! && !Copy
        x
    else
        # Since SciML problems and integrators are tightly coupled we need to
        # remake the problem and then reinitialize the integrator if we want
        # a Model copy. Remaking JumpProblem only allows changing a limited
        # subset of the properties, and I am unsure which ones are aliased in
        # the process. To avoid trouble, we choose to simply extract the
        # current state to a FlatState and then proceed as if this were a new
        # model. Presumably this is slower than calling remake, yet safer, and
        # anyway could only be avoided when we are branching the simulation
        # without changing models.
        Models.adapt(FlatState(x), f!)
    end

Models.adapt(x::FlatState, f!::JumpModel, _copy) = JumpState(
    problem = JumpProcesses.JumpProblem(
        f!.system,
        JumpProcesses.DiscreteProblem(
            f!.system,
            [
                s => get(x.counts, normalize_name(s), 0)
                for s in ModelingToolkit.states(f!.system)
            ],
            (x.t, Inf),
            f!.parameters,
        ),
        f!.method,
        rng = x.randomness,
    );
    f!,
)

function Models.each_event(callback::Function, x::JumpState)
    solution = x.integrator.sol

    names = normalize_name.(
        ModelingToolkit.SymbolicIndexingInterface.variable_symbols(solution)
    )
    # ^ We assume that this access is safe and the order agrees with the values
    # in x.integrator.sol.u because this is how SciMLBase constructs the Table
    # reinterpretation in Tables.rows(::AbstractTimeseriesSolution).

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

function (f!::JumpModel)(x::JumpState, Δt::Float64; into = nothing, _...)
    isfinite(Δt) || error("cannot do this forever")

    empty!(x.integrator.sol.u)
    empty!(x.integrator.sol.t)
    x.integrator.opts.callback.discrete_callbacks[1].affect!.t0 = Models.t(x)

    @logmsg Progress :stepping at = "JumpModel" todo = Δt
    if into !== nothing
        x.integrator.save_everystep = true
        ModelingToolkit.savevalues!(x.integrator, true)
        ModelingToolkit.step!(x.integrator, Δt, true)
    else
        x.integrator.save_everystep = false
        ModelingToolkit.step!(x.integrator, Δt, true)
        ModelingToolkit.savevalues!(x.integrator, true)
    end
    @logmsg Progress :done at = "JumpModel"

    x
end

end
