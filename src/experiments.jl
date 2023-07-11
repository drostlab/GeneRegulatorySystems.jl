module Experiments

using ..Models: Model
import ..Simulations
import ..Extraction
import ..Specifications: Specifications, Specification

using Base: @kwdef

@kwdef struct Experiment
    label::String
    initial::AbstractDict{Symbol}
    model::Model
    takes::Vector{Simulations.Take}
    extract::Extraction.Scheme
    simulation_seed::String
    extraction_seed::String
    channel::String
    specification::AbstractDict{Symbol} = Dict{Symbol}()
end

Experiment(specification::AbstractDict{Symbol}) = Experiment(;
    label = specification[:label],
    model = Model(specification[:model]),
    initial = specification[:initial],
    takes = Simulations.takes(specification[:take]),
    extract = Extraction.Scheme(get(specification, :extract, nothing)),
    simulation_seed = specification[:simulation_seed],
    extraction_seed = specification[:extraction_seed],
    channel = specification[:channel],
    specification
)

experiments(specification::Specification) =
    (Experiment(s) for s in Specifications.unroll(specification))

locate_definition(experiment::Experiment, symbol::Symbol) =
    repr("text/plain", experiment.specification[Symbol("^$symbol")])

end
