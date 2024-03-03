module GeneRegulatorySystems

import JSON
using PrecompileTools

import Random
import SHA

randomness(seed::AbstractVector{UInt64}) = Random.Xoshiro(seed...)
randomness(seed::AbstractString) =
    randomness(reinterpret(UInt64, SHA.sha256(seed)))

seed(::Random.AbstractRNG) = nothing
seed(r::Random.Xoshiro) = [r.s0, r.s1, r.s2, r.s3]

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

const SPECIFICATION_EXAMPLES = "$(@__DIR__)/../examples/specification"

@compile_workload begin
    load(path) = JSON.parsefile(
        "$SPECIFICATION_EXAMPLES/$path";
        dicttype = Dict{Symbol, Any}
    )
    dryrun(_primitive!, _x, _Δt; _...) = nothing
    trace(_into, _state; _...) = nothing

    # Load and dry-run all specification examples:
    for filename in readdir(SPECIFICATION_EXAMPLES)
        schedule! = Schedule(
            specification = Specification(
                Dict(:step => Dict(:< => filename))
            )
        )
        schedule!(Models.FlatState(); load, dryrun)
    end

    # Load and additionally describe and simulate some examples:
    examples = [
        (filename = "kronecker.schedule.json", path = "+++-2"),
        (filename = "templating.schedule.json", path = "+++-1.do"),
        (filename = "differentiation.schedule.json", path = "+++.do"),
        #(filename = "random-differentiation.schedule.json", path = "+++.do"),
    ]
    for (; filename, path) in examples
        schedule! = Schedule(
            specification = Specification(
                Dict(:step => Dict(:< => filename))
            )
        )
        Models.describe(Scheduling.reify(schedule!, path; load))
        schedule!(Models.FlatState(); load, trace)
    end
end

end
