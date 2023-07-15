module GeneRegulatorySystems

import Random
import SHA

randomness(seed::AbstractString) =
    Random.Xoshiro(reinterpret(UInt64, SHA.sha256(seed))...)

σ(x) = inv(one(x) + exp(-x))
logit(p) = log(p / (one(p) - p))

include("conversion.jl")
include("models/models.jl")
include("simulation.jl")
include("extraction.jl")
include("specifications.jl")
include("experiments.jl")

using .Simulation: simulate
export Specifications, Experiments, Models, Simulation, simulate

end
