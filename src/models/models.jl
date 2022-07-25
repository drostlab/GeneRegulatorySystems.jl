module Models

abstract type Parameters end

load(specification::AbstractDict{Symbol, Any}) =
    load(Val(Symbol(specification[:kind])), specification)

initialize(initial, θ::Parameters) = throw("unimplemented")

regulate!(rates, state, θ::Parameters) = throw("unimplemented")

apply!(state, i, θ::Parameters) = throw("unimplemented")

# TODO: validate model specification

include("vanilla.jl")

end