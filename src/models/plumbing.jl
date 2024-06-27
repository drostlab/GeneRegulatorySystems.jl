module Plumbing

import ....GeneRegulatorySystems
using ..Models: Models, Model, Instant, FlatState, Branched
import ..Specifications

struct Pass <: Model{Any} end

(::Pass)(x, _Δt::Float64; _...) = x

struct Seed <: Instant{FlatState}
    seed::String
end

Specifications.constructor(::Val{:seed}) = Seed

function (f!::Seed)(x::FlatState, _Δt::Float64 = Inf; _...)
    x.randomness = GeneRegulatorySystems.randomness(f!.seed)
    x
end

struct Filter <: Instant{FlatState}
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

flatten(xs::AbstractDict{Symbol}; T = Any) =
    mapreduce(merge, xs) do (key, value)
        if value isa AbstractDict{Symbol}
            Dict{Symbol, T}(
                Symbol("$(key).$(key′)") => value′
                for (key′, value′) in flatten(value)
            )
        else
            Dict{Symbol, T}(key => value)
        end
    end

struct Adjust <: Instant{FlatState}
    adjust::Function
    adjustment::Dict{Symbol, Real}

    function Adjust(adjust, adjustment)
        all(values(adjustment) .≥ zero(valtype(adjustment))) ||
            error("adjustment must be nonnegative")
        new(adjust, adjustment)
    end
end

adder(counts::AbstractDict{Symbol}) = Adjust(+, flatten(counts, T = Int))
multiplier(counts::AbstractDict{Symbol}) = Adjust(*, flatten(counts, T = Real))
setter(counts::AbstractDict{Symbol}) =
    Adjust(last ∘ Pair, flatten(counts, T = Int))

Specifications.constructor(::Val{:set}) = setter
Specifications.constructor(::Val{:add}) = adder
Specifications.constructor(::Val{:multiply}) = multiplier

function (f!::Adjust)(x::FlatState, _Δt::Float64; _...)
    mergewith!(Base.Fix1(floor, Int) ∘ f!.adjust, x.counts, f!.adjustment)
    x
end

struct Merge <: Instant{Branched}
    merge::Function
end

merger(operation::AbstractString) = operation |> Symbol |> Val |> merger
merger(::Val{:+}) = Merge(+)

Specifications.constructor(::Val{:merge}) = merger

function (f!::Merge)(x::Branched, _Δt::Float64; _...)
    accumulator = FlatState(
        t = Models.t(x.stem),
        randomness = Models.randomness(x.stem),
    )
    for b in x.branches
        b′ = b isa FlatState ? b : FlatState(b)
        mergewith!(f!.merge, accumulator.counts, b′.counts)
    end
    accumulator
end

end
