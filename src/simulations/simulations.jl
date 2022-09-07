module Simulations

import ..Models

using Random

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

include("gillespie.jl")

simulate(
    initial,
    θ::Models.Parameters;
    takes,
    randomness::AbstractRNG = Xoshiro(0)
) = Simulations.Gillespie.simulate(
    initial,
    θ;
    takes = Simulations.takes(takes),
    randomness
)

end
