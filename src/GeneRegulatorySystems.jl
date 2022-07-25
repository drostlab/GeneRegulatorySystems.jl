module GeneRegulatorySystems

include("models/models.jl")
include("simulation/simulation.jl")

using Random

Take = Simulation.Take

export simulate, Take

simulate(
    initial,
    θ::Models.Parameters;
    takes,
    randomness::AbstractRNG = MersenneTwister(0)
) = Simulation.Gillespie.simulate(
    initial,
    θ;
    takes = Simulation.takes(takes),
    randomness
)

end # module
