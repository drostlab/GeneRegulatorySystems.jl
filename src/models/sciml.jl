module SciML

import ...Conversion: cast
using ..Models: Models, Model, FlatState

import JumpProcesses
import ModelingToolkit

using Random
using Logging: LogLevel, @logmsg

Progress = LogLevel(-2)

normalize_name(s) =
    Symbol(replace(String(ModelingToolkit.getname(s)), '₊' => '.'))

@kwdef mutable struct ProgressTrigger
    i::Int = 0
end

function (trigger::ProgressTrigger)(_u, _t, _integrator)
    trigger.i += 1
    trigger.i % 10000 == 0
end

progress(integrator) = @logmsg(
    Progress,
    :stepping,
    at = "JumpModel",
    done = integrator.t - integrator.sol.prob.tspan[1],
)

@kwdef struct JumpState
    f!::Model{JumpState}
    problem::JumpProcesses.JumpProblem
    integrator::JumpProcesses.SSAIntegrator = ModelingToolkit.init(
        problem,
        JumpProcesses.SSAStepper(),
        save_start = false,
        callback = JumpProcesses.DiscreteCallback(
            ProgressTrigger(),
            progress,
            save_positions = (false, false),
        ),
    )
end

Models.t(x::JumpState) = x.integrator.t

cast(::Type{FlatState}, x::JumpState) = FlatState(
    counts = Dict(
        normalize_name(s) => x.integrator[s]
        for s in ModelingToolkit.SymbolicIndexingInterface.variable_symbols(
            x.integrator
        )
    ),
    randomness = x.problem.rng;
    x.integrator.t,
)

@kwdef struct JumpModel{Definition} <: Model{JumpState}
    definition::Definition
    system::ModelingToolkit.JumpSystem
    method::JumpProcesses.AbstractAggregatorAlgorithm
    parameters
end

Models.describe(f!::SciML.JumpModel) = Models.describe(f!.definition)

Models.adapt(x::JumpState, f!::JumpModel, ::Val{Copy}) where Copy =
    if x.f! === f! && !Copy
        # We need to drop any previous solution transcripts, but there doesn't
        # seem to be a way to clear x.integrator.sol, and reinit!, set_t! and
        # empty! are not implemented for JumpProcesses.SSAIntegrator so that we
        # cannot just call init again either, thus we have to remake the
        # problem with the new starting time point. Since according to
        # documentation remaking JumpProblems will partially alias state, in
        # case a copy is required we will take the detour via FlatState in the
        # other branch.
        JumpState(
            problem = ModelingToolkit.remake(
                x.problem,
                tspan = (x.integrator.t, Inf),
                u0 = x.integrator.u,
            );
            f!,
        )
    else
        adapt(cast(FlatState, x), f!)
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

Models.adapt(x::JumpState, f!::Model, _copy) =
    Models.adapt(cast(FlatState, x), f!)

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
