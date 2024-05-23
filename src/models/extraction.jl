module Extraction

using ...Specifications: Specifications, Template, Scope, List, Each, reference
using ..Scheduling: Schedule
using ..Plumbing: Filter, Pass
using ..Resampling: ResampleEachBinomial
using ..Resampling: ResampleEachAccumulate
using ..Resampling: ResampleTargetMeanEachBinomial

import Distributions

with_intermediate_output_suppressed(specifications...) = Scope(
    definitions = Dict(
        :into => Template(nothing),
        :into′ => reference(:into),
        :channel′ => reference(:channel),
    ),
    step = List([
        specifications...
        Scope(
            definitions = Dict(
                :into => reference(:into′),
                :channel => reference(:channel′),
            ),
            step = Template(Pass()),
        )
    ]),
)

simple_proteome(specification::AbstractDict{Symbol}) =
    with_intermediate_output_suppressed(
        Template(Filter(r"\.proteins$")),
        Template(
            ResampleTargetMeanEachBinomial(μ = get(specification, :target, Inf))
        ),
    )

Specifications.constructor(::Val{Symbol("extract-proteome-simple")}) =
    simple_proteome

simple_transcriptome(specification::AbstractDict{Symbol}) =
    with_intermediate_output_suppressed(
        Template(Filter(r"\.(pre)?mrnas$")),
        Template(
            ResampleTargetMeanEachBinomial(μ = get(specification, :target, Inf))
        ),
    )

Specifications.constructor(::Val{Symbol("extract-transcriptome-simple")}) =
    simple_transcriptome

function amplified_transcriptome(specification::AbstractDict{Symbol})
    p₀ = get(specification, :collect, 1.0)
    0.0 ≤ p₀ ≤ 1.0 || error("invalid collect probability")

    cycles = get(specification, :cycles, 0)
    0 ≤ cycles || error("invalid cycle count")

    dropout = get(specification, :dropout, 0.0)
    efficiency = get(specification, :efficiency, 1.0)
    ps = [dropout, 1.0 - dropout - efficiency, efficiency]
    Distributions.isprobvec(ps) || error("invalid amplification settings")

    target = get(specification, :target, Inf)

    with_intermediate_output_suppressed(
        Template(Filter(r"\.(pre)?mrnas$")),
        Template(ResampleEachBinomial(p = p₀)),
        Each(
            items = Template(range(length = cycles)),
            step = Template(ResampleEachAccumulate(ps)),
        ),
        Template(ResampleTargetMeanEachBinomial(μ = target)),
    )
end

Specifications.constructor(::Val{Symbol("extract-transcriptome-amplified")}) =
    amplified_transcriptome

end
