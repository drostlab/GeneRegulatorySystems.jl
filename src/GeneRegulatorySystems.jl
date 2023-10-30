module GeneRegulatorySystems

import Random
import SHA

randomness(seed::AbstractString) =
    Random.Xoshiro(reinterpret(UInt64, SHA.sha256(seed))...)

σ(x) = inv(one(x) + exp(-x))
logit(p) = log(p / (one(p) - p))

include("conversion.jl")
include("specifications.jl")
include("models/models.jl")

using .Specifications: Specification
using .Models.Scheduling: Scheduling, Schedule

export Specifications
export Specification
export Models
export Scheduling
export Schedule

end
