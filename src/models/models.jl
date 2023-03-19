module Models

import ModelingToolkit
import Symbolics

abstract type Model end

# TODO defn static groups(model) -- genes
# TODO defn static kinds(model) -- species kinds inside genes
# TODO defn model specification validation

Model(specification::AbstractDict{Symbol, Any}) =
    Model(Symbol(specification[:kind]), specification)

Model(kind::Symbol, specification::AbstractDict{Symbol, Any}) =
    Model(Val(kind), specification)

prepare_initial(specification::AbstractDict{Symbol}, θ::Model) =
    throw("unimplemented")

collect(transcript, θ::Model) = throw("unimplemented")

abstract type GillespieModel <: Model end
initialize(initial, θ::GillespieModel) = throw("unimplemented")
regulate!(rates, state, θ::GillespieModel) = throw("unimplemented")
apply!(state, i, θ::GillespieModel) = throw("unimplemented")

Base.@kwdef struct SciMLJumpModel <: Model
    system::ModelingToolkit.JumpSystem
    method  # ::AbstractAggregatorAlgorithm
    parameters
end

function prepare_initial(
    specification::AbstractDict{Symbol},
    θ::SciMLJumpModel,
)
    lookup(leaf, _path, _default) = leaf
    lookup(nested, symbol::Symbol, default) =
        lookup(nested, Symbol.(split(String(symbol), '₊')), default)
    function lookup(
        nested::AbstractDict{Symbol},
        path::AbstractVector{Symbol},
        default,
    )
        first, tail... = path  # fail if empty: Dict value disallowed
        lookup(get(nested, first, default), tail, default)
    end

    [
        s => lookup(specification, Symbolics.tosymbol(s, escape = false), 0)
        for s in ModelingToolkit.states(θ.system)
    ]
end

function collect(transcript, θ::SciMLJumpModel)
    normalize_symbol(s) = Symbol(
        replace(
            String(Symbolics.tosymbol(s, escape = false)),
            '₊' => '.',
        )
    )

    (;
        :t => transcript.t,
        (
            normalize_symbol(s) => transcript[s]
            for s in ModelingToolkit.states(θ.system)
        )...,
        # TODO: add back rates
    )
end

include("vanilla.jl")

end