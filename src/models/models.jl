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

Model(specification::AbstractDict{Symbol, Any}) =
    Model(Symbol(specification[:kind]), specification)

Model(kind::Symbol, specification::AbstractDict{Symbol, Any}) =
    Model(Val(kind), specification)

describe(θ::Model) = throw("unimplemented")
prepare_initial(specification::AbstractDict{Symbol}, θ::Model) =
    throw("unimplemented")
collect(transcript, θ::Model) = throw("unimplemented")

abstract type GillespieModel <: Model end
initialize(initial, θ::GillespieModel) = throw("unimplemented")
regulate!(rates, state, θ::GillespieModel) = throw("unimplemented")
apply!(state, i, θ::GillespieModel) = throw("unimplemented")

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

coerce(T::Type, x::AbstractDict{Symbol}, ::Val{K}; context) where {K} =
    coerce(fieldtype(T, K), x[K]; context)
coerce(::Type{Symbol}, x; _...) = Symbol(x)
coerce(T::Type{<:Real}, x::Real; _...) = convert(T, x)
coerce(T::Type{<:Real}, x::AbstractString; _...) = parse(T, x)
coerce(::Type{Vector{T}}, xs::AbstractVector; context) where {T} =
    coerce.(T, xs; context)
coerce(T::Type, x::AbstractDict{Symbol}; context = x) = T(; (
    key => coerce(T, x, Val(key); context)
    for key in keys(x)
    if hasfield(T, key)
)...)
coerce(::Type{Union{Some{T}, Nothing}}, ::Nothing; _...) where {T} = nothing
coerce(::Type{Union{Some{T}, Nothing}}, x; context) where {T} =
    Some(coerce(T, x; context))
coerce(  # disambiguation
    ::Type{Union{Some{T}, Nothing}},
    x::AbstractDict{Symbol};
    context,
) where {T} = Some(coerce(T, x; context))

include("vanilla.jl")
include("kronecker.jl")

end