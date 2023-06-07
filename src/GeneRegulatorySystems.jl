module GeneRegulatorySystems

import Random
import SHA

randomness(seed::AbstractString) =
    Random.Xoshiro(reinterpret(UInt64, SHA.sha256(seed))...)

σ(x) = inv(one(x) + exp(-x))
logit(p) = log(p / (one(p) - p))

include("models/models.jl")
include("simulations/simulations.jl")
include("specifications.jl")

using .Simulations: simulate
export Specifications, Models, Simulations, simulate

end
