module Plumbing

import ....GeneRegulatorySystems
using ...Conversion: cast
using ..Models: Model, FlatState, Branched, flatten
import ..Specifications

struct Pass <: Model{Any} end

(::Pass)(x, _Δt::Float64; _...) = x

struct Seed <: Model{FlatState}
    seed::String
end

Specifications.constructor(::Val{:seed}) = Seed

function (f!::Seed)(x::FlatState, _Δt::Float64 = Inf; _...)
    x.randomness = GeneRegulatorySystems.randomness(f!.seed)
    x
end

struct Filter <: Model{FlatState}
    kinds::Regex
end
Filter(s::AbstractString) = Filter(Regex(s))

Specifications.constructor(::Val{:filter}) = Filter

function (f!::Filter)(x::FlatState, _Δt::Float64; _...)
    for key in keys(x.counts)
        if isnothing(match(f!.kinds, String(key)))
            delete!(x.counts, key)
        end
    end
    x
end

struct Adjust <: Model{FlatState}
    adjust::Function
    adjustment::Dict{Symbol, Int}
end

setter(counts::AbstractDict{Symbol}) = Adjust(last ∘ Pair, flatten(counts))
adder(counts::AbstractDict{Symbol}) = Adjust(+, flatten(counts))
grower(counts::AbstractDict{Symbol}) = Adjust(*, flatten(counts))

Specifications.constructor(::Val{:set}) = setter
Specifications.constructor(::Val{:add}) = adder
Specifications.constructor(::Val{:grow}) = grower

function (f!::Adjust)(x::FlatState, _Δt::Float64; _...)
    mergewith!(f!.adjust, x.counts, f!.adjustment)
    x
end

struct Merge <: Model{Branched}
    merge::Function
end

merger(operation::AbstractString) = operation |> Symbol |> Val |> merger
merger(::Val{:+}) = Merge(+)

Specifications.constructor(::Val{:merge}) = merger

function (f!::Merge)(x::Branched, _Δt::Float64; _...)
    accumulator = cast(FlatState, x)
    empty!(accumulator.counts)
    for b in x.branches
        mergewith!(f!.merge, accumulator.counts, cast(FlatState, b).counts)
    end
    accumulator
end

end
