"""
Contains predefined `Instant` observation models to simulate extraction of
-omics data from the system state.

These recipes assemble some of the primitives defined in
[`Resampling`](@ref GeneRegulatorySystems.Models.Resampling) into
[`Schedule`](@ref)s, additionally wrapping the corresponding specifications to
suppress intermediate output.
"""
module Extraction

using ...Specifications: Specifications, Template, Scope, List, Each, reference
using ..Scheduling: Schedule
using ..Plumbing: Filter, Pass
using ..Resampling:
    ResampleEachBinomial,
    ResampleEachAccumulate,
    ResampleTargetMeanEachBinomial

import Distributions

"""
    with_intermediate_output_suppressed(specifications...)

Transform an extraction specification such that the corresponding `Schedule`
will only emit output once at the end.

This is used by the extraction schemes to behave more like a unit (instead of
the composite [`Schedule`](@ref) they actually are).
"""
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

"""
    simple_proteome(specification::AbstractDict{Symbol})

Construct an `Instant` naive extraction model that independently samples
proteins to achieve a specified target of the expected total count.

Specifically, this constructs a `Schedule` that just drops all non-protein
molecular species and then applies [`ResampleTargetMeanEachBinomial`](@ref).
Intermediate output [is suppressed](@ref with_intermediate_output_suppressed).

## Specification

In JSON, `simple_proteome` is specified as a JSON object
```
{"{extract-proteome-simple}": {"target": <target>}}
```
where `<target>` is a JSON number specifying the expected total count to aim
for.

The result will be equivalent to
```
{"step": [
    {"{filter}": "\\\\.proteins\$"},
    {"{resample-target-mean-each-binomial}": <target>}
]}
```
with intermediate output suppressed.
"""
simple_proteome(specification::AbstractDict{Symbol}) =
    with_intermediate_output_suppressed(
        Template(Filter(r"\.proteins$")),
        Template(
            ResampleTargetMeanEachBinomial(μ = get(specification, :target, Inf))
        ),
    )

Specifications.constructor(::Val{Symbol("extract-proteome-simple")}) =
    simple_proteome

"""
    simple_transcriptome(specification::AbstractDict{Symbol})

Construct an `Instant` naive extraction model that independently samples
transcripts (`premrnas` and `mrnas`) to achieve a specified target of the
expected total count.

Specifically, this constructs a `Schedule` that just drops all non-transcript
molecular species and then applies [`ResampleTargetMeanEachBinomial`](@ref).
Intermediate output [is suppressed](@ref with_intermediate_output_suppressed).

## Specification

In JSON, `simple_transcriptome` is specified as a JSON object
```
{"{extract-transcriptome-simple}": {"target": <target>}}
```
where `<target>` is a JSON number specifying the expected total count to aim
for.

The result will be equivalent to
```
{"step": [
    {"{filter}": "\\\\.(pre)?mrnas\$"},
    {"{resample-target-mean-each-binomial}": <target>}
]}
```
with intermediate output suppressed.
"""
simple_transcriptome(specification::AbstractDict{Symbol}) =
    with_intermediate_output_suppressed(
        Template(Filter(r"\.(pre)?mrnas$")),
        Template(
            ResampleTargetMeanEachBinomial(μ = get(specification, :target, Inf))
        ),
    )

Specifications.constructor(::Val{Symbol("extract-transcriptome-simple")}) =
    simple_transcriptome

"""
    amplified_transcriptome(specification::AbstractDict{Symbol})

Construct an `Instant` extraction model that simulates multiple rounds of
amplification by PCR. The procedure is fairly simple:
1. Drop all non-transcript molecular species.
2. Retain each molecule independently with probability `collect` (applying
   [`ResampleEachBinomial`](@ref)).
3. Repeat the following resampling procedure
   ([`ResampleTargetMeanEachBinomial`](@ref)) `cycles` many times: For each
   molecule independently, either remove it with probability `dropout`, or copy
   it with probability `efficiency`, or otherwise leave it as is.
4. Retain each molecule independently with the same probability such that the
   expected total count is `target` (applying
   [`ResampleTargetMeanEachBinomial`](@ref)).

Intermediate output [is suppressed](@ref with_intermediate_output_suppressed).

## Specification

In JSON, `amplified_transcriptome` is specified as a JSON object
```
{"{extract-transcriptome-amplified}": {
    "collect": <collect>,
    "cycles": <cycles>,
    "efficiency": <efficiency>,
    "dropout": <dropout>,
    "target": <target>
}}
```
where `<cycles>` is a JSON (integer) number and `<collect>`, `<efficiency>`,
`<dropout>` and `<target>` are JSON numbers specifying the extraction parameters
as defined above.

The result will be equivalent to
```
{"step": [
    {"{filter}": "\\\\.(pre)?mrnas\$"},
    {"{resample-each-binomial}": <collect>},
    {"each": {"length": <cycles>}, "step": {
        "{resample-each-accumulate}": [<dropout>, <...>, <efficiency>]
    }},
    {"{resample-target-mean-each-binomial}": <target>}
]}
```
with intermediate output suppressed, where `<...>` = 1.0 - `<efficiency>` -
`<dropout>`.
"""
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
