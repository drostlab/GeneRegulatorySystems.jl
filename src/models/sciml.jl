module SciML

import ...Conversion: cast
using ..Models: Models, Model, FlatState

import JumpProcesses
import ModelingToolkit
import Symbolics

using Base: @kwdef
using Random
using Logging: LogLevel, @logmsg

Progress = LogLevel(-2)

normalize_symbol(s) =
    Symbol(replace(String(Symbolics.tosymbol(s, escape = false)), '₊' => '.'))

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
        normalize_symbol(s) => x.integrator[s]
        for s in ModelingToolkit.states(x.integrator.f.sys)
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
                s => get(x.counts, normalize_symbol(s), 0)
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


function Models.table(x::JumpState; sorted)
    transcript = Dict(
        normalize_symbol(s) => x.integrator.sol[s]
        for s in ModelingToolkit.states(x.integrator.f.sys)
    )

    ks = keys(transcript)
    if sorted
        ks = sort!(collect(ks))
    end

    (; x.integrator.sol.t, (k => transcript[k] for k in ks)...)
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
