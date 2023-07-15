module Simulation

import ..Models

using Random

using JumpProcesses

Base.@kwdef struct Take
    event_resolution::Int = 1
    from::Float64 = 0.0
    step::Float64 = 0.0
    to::Float64
end
Take(take::AbstractDict{Symbol}) = Take(; take...)
Take(at::Float64) = Take(; from = at, step = 1.0, to = at)

takes(xs::AbstractVector{Take}) = xs
takes(xs::AbstractVector) = Take.(xs)
takes(x::Take) = [x]
takes(x) = [Take(x)]

function simulate(
    θ::Models.SciMLJumpModel,
    initial_specification,
    takes::AbstractVector{Take};
    randomness::AbstractRNG
)
    initial = Models.prepare_initial(initial_specification, θ)
    problem = JumpProblem(
        θ.system,
        DiscreteProblem(
            θ.system,
            initial,
            (0.0, maximum(take.to for take in takes)),
            θ.parameters,
        ),
        θ.method,
        rng = randomness,
    )

    integrator = init(problem, SSAStepper(), save_start = false)
    integrator.save_everystep = false
    # ^ cannot be set on `init` -- see JumpProcesses.jl #306
    for take in takes
        if take.step > 0.0  # sample slices
            for next in take.from:take.step:take.to
                step!(integrator, max(0.0, next - integrator.t), true)
                savevalues!(integrator, true)
                # This is not strictly equivalent to the behavior in
                # `Simulations.Gillespie` if the take already lies in the past
                # (which can happen if the takes are misspecified); there this
                # will emit a record at `next` while here we will just create
                # one at the current timepoint. I think this divergence is fine
                # for now.
            end
        else  # full take
            step!(integrator, max(0.0, take.from - integrator.t), true)
            integrator.save_everystep = true
            step!(integrator, max(0.0, take.to - integrator.t), true)
            integrator.save_everystep = false
        end
    end

    integrator.sol
end

end
