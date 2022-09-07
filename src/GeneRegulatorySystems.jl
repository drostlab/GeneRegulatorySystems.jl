module GeneRegulatorySystems

include("models/models.jl")
include("simulations/simulations.jl")

using .Simulations: simulate, Take
export simulate, Take

end # module
