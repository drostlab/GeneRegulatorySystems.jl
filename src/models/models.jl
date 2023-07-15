module Models

using Base: @kwdef
using Random

import ModelingToolkit
import Symbolics

abstract type Model end

@kwdef struct ModelDescription
    species_kinds
    species_groups
    links
end

# TODO defn model specification validation

Model(specification::AbstractDict{Symbol}) =
    Model(Symbol(specification[:kind]), specification)

Model(kind::Symbol, specification::AbstractDict{Symbol}) =
    Model(Val(kind), specification)

describe(θ::Model) = error("unimplemented")
prepare_initial(specification::AbstractDict{Symbol}, θ::Model) =
error("unimplemented")
collect(transcript, θ::Model) = error("unimplemented")

@kwdef struct SciMLJumpModel <: Model
    system::ModelingToolkit.JumpSystem
    method  # ::AbstractAggregatorAlgorithm
    parameters
    description::ModelDescription
end

describe(θ::SciMLJumpModel) = θ.description

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
        sort([
            normalize_symbol(s) => transcript[s]
            for s in ModelingToolkit.states(θ.system)
        ])...,
        # TODO: add back rates
    )
end

include("vanilla.jl")
include("kronecker.jl")

end