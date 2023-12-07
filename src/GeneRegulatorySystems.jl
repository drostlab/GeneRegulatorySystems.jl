module GeneRegulatorySystems

import JSON
using PrecompileTools

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

const SPECIFICATION_EXAMPLES = "$(@__DIR__)/../examples/specification"

@compile_workload begin
    load(path) = JSON.parsefile(
        "$SPECIFICATION_EXAMPLES/$path";
        dicttype = Dict{Symbol, Any}
    )
    dryrun(_primitive!, _x, _Δt; _...) = nothing
    trace(_into, _state; _...) = nothing
    for filename in readdir(SPECIFICATION_EXAMPLES)
        schedule! = Schedule(
            specification = Specification(
                Dict(:seed => "seed", :step => Dict(:< => filename))
            )
        )
        schedule!(Models.FlatState(); load, dryrun)
    end

    kronecker_schedule! = Schedule(
        specification = Specification(
            Dict(:seed => "seed", :step => Dict(:< => "SKG.schedule.json"))
        )
    )
    Models.describe(Scheduling.reify(kronecker_schedule!, "+++"; load))
    kronecker_schedule!(Models.FlatState(); load, trace)

    templating_schedule! = Schedule(
        specification = Specification(
            Dict(
                :seed => "seed",
                :step => Dict(:< => "templating.schedule.json"),
            )
        )
    )
    Models.describe(Scheduling.reify(templating_schedule!, "++-5.do"; load))

end

end
