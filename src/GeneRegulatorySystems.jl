module GeneRegulatorySystems

import JSON
using PrecompileTools

import Random
import SHA

const DEFAULTS = "$(@__DIR__)/defaults.specification.json"
const SPECIFICATION_EXAMPLES = "$(@__DIR__)/../examples/specification"

randomness(seed::AbstractVector{UInt64}) = Random.Xoshiro(seed...)
randomness(seed::AbstractString) =
    randomness(reinterpret(UInt64, SHA.sha256(seed)))

seed(::Random.AbstractRNG) = nothing
seed(r::Random.Xoshiro) = [r.s0, r.s1, r.s2, r.s3]

σ(x) = inv(one(x) + exp(-x))
logit(p) = log(p / (one(p) - p))

load_defaults() = JSON.parsefile(DEFAULTS, dicttype = Dict{Symbol, Any})

include("conversion.jl")
include("specifications.jl")
include("models/models.jl")

using .Specifications: Specification
using .Models.Scheduling: Scheduling, Schedule

load_schedule(path::AbstractString; seed = "seed") = Scheduling.load_schedule(
    Schedule(
        specification = Specifications.Load(basename(path)),
        bindings =  Dict{Symbol, Any}(
            :into => "",
            :channel => "",
            :defaults => load_defaults(),
            :seed => seed,
        ),
    ),
    load = p -> JSON.parsefile(
        "$(dirname(path))/$p",
        dicttype = Dict{Symbol, Any},
    ),
)

export Specifications
export Specification
export Models
export Scheduling
export Schedule
export load_schedule

@compile_workload begin
    dryrun(_primitive!, _x, _Δt; _...) = nothing
    trace(_into, _state; _...) = nothing

    # Load and dry-run all specification examples:
    for filename in readdir(SPECIFICATION_EXAMPLES)
        schedule! = load_schedule("$SPECIFICATION_EXAMPLES/$filename")
        schedule!(; dryrun)
    end

    # Load and additionally describe and simulate some examples:
    examples = [
        (filename = "kronecker.schedule.json", path = "+-2"),
        (filename = "templating.schedule.json", path = "+-1.do"),
        (filename = "differentiation.schedule.json", path = "+.do"),
    ]
    for (; filename, path) in examples
        schedule! = load_schedule("$SPECIFICATION_EXAMPLES/$filename")
        Models.describe(Scheduling.reify(schedule!, path))
        schedule!(; trace)
    end
end

end
