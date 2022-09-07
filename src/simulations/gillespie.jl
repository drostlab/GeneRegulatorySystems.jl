module Gillespie

import ..Simulations
import ...Models

using Random
using StatsBase

function sample_reaction(h; randomness)
    weights = Weights(h)
    Δt = -log(rand(randomness)) / sum(weights)
    μ = sample(randomness, weights)

    Δt, μ
end

function simulate!(
    state,
    rates,
    θ::Models.Parameters;
    randomness,
    t,
    next_reaction,
    take::Simulations.Take,
    transcript,
)
    function step!()
        Models.apply!(state, next_reaction, θ)
        Models.regulate!(rates, state, θ)
        Δt, next_reaction = sample_reaction(rates; randomness)
        t += Δt
    end

    function record!(; t)
        push!(transcript.ts, t)
        push!(transcript.states, copy(state))
        push!(transcript.rates, copy(rates))
    end

    if take.step > 0.0  # sample slices
        for next in take.from:take.step:take.to
            while t < next
                step!()
            end
            record!(t = next)
        end
    else  # full take
        while t < take.from
            step!()
        end
        for i in Iterators.countfrom(1)
            t < take.to || break
            now = t
            step!()
            if i % take.event_resolution == 0
                record!(t = now)
            end
        end
        record!(t = take.to)
    end

    t, next_reaction
end

function simulate(
    initial,
    θ::Models.Parameters;
    takes::AbstractVector{Simulations.Take},
    randomness::AbstractRNG
)
    t = 0.0
    state, rates = Models.initialize(initial, θ)
    Models.regulate!(rates, state, θ)

    transcript = (;
        ts = typeof(t)[],
        states = typeof(state)[],
        rates = typeof(rates)[],
    )

    Δt, next_reaction = sample_reaction(rates; randomness)
    t += Δt
    for take in takes
        t, next_reaction = simulate!(
            state,
            rates,
            θ;
            randomness,
            t,
            next_reaction,
            take,
            transcript
        )
    end

    transcript
end

end
