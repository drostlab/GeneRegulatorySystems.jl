module Models

abstract type Parameters end
Parameters(specification::AbstractDict{Symbol, Any}) =
    Parameters(Val(Symbol(specification[:kind])), specification)

initialize(initial, θ::Parameters) = throw("unimplemented")

regulate!(rates, state, θ::Parameters) = throw("unimplemented")

apply!(state, i, θ::Parameters) = throw("unimplemented")

# TODO: validate model specification

include("vanilla.jl")

end