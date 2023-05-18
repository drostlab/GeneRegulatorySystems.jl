module ExperimentTool

if nameof(parentmodule(@__MODULE__)) == :GeneRegulatorySystemsTools
    @eval using GeneRegulatorySystemsTools: Common
else
    include("$(@__DIR__)/../common.jl")
end

using .Common: repository_version, path

import Dates
using Random
import SHA

# NOTE: This module lazily imports additional modules in `main`.

randomness(seed::AbstractString) =
    Xoshiro(reinterpret(UInt64, SHA.sha256(seed))...)

function map_paths(paths)
    preliminary_map = Dict(p => basename(p) for p in paths)
    if allunique(vcat(path(:specification), values(preliminary_map)...))
        return preliminary_map
    else
        return Dict(p => "_$(i)_$(basename(p))" for (i, p) in enumerate(paths))
    end
end

function assert_compatible_versions(specification)
    if (specification.bindings[:_julia_version] != "v$VERSION")
        @error(
            "Experiment was prepared with a different Julia version.",
            specification.bindings[:_julia_version],
            "v$VERSION",
        )
        @info "This is disallowed to ensure reproducibility."
        throw(:help)
    end

    if (specification.bindings[:_version] != repository_version())
        @error(
            "Experiment was prepared with a different " *
            "GeneRegulatorySystems.jl version.",
            specification.bindings[:_version],
            repository_version(),
        )
        @info "This is disallowed to ensure reproducibility."
        throw(:help)
    end
end

function prepare!(; location, specifications, seed)
    specification_path = path(:specification; prefix = location)
    if ispath(specification_path)
        @error(
            "Cannot prepare experiment, specification already exists.",
            specification_path,
        )
        throw(:help)
    elseif isempty(specifications)
        @error "No specifications given to be prepared."
        throw(:help)
    else
        paths = realpath.(specifications)
        path_map = map_paths(paths)
        wrapped = [
            Dict(:< => basename("$(location)$(path_map[p])"))
            for p in paths
        ]

        mkpath(dirname(specification_path))
        for (source, target) in path_map
            cp(source, "$(location)$target"; follow_symlinks = true)
        end
        open(specification_path, "w") do file
            JSON.print(
                file,
                Dict(
                    :seed => seed,
                    :in => length(wrapped) == 1 ? only(wrapped) : wrapped,
                    :_version => repository_version(),
                    :_julia_version => "v$VERSION",
                    :_defaults => Dict(
                        :simulation_seed => raw"$seed-$^item",
                        :label => raw"$^item",
                        :channel => raw"$^model",
                        :initial => Dict{Symbol, Any}()
                    ),
                ),
                4,
            )
        end
    end
end

function simulate!(; location)
    loader(path) = JSON.parsefile(
        "$(dirname(location))/$path";
        dicttype = Dict{Symbol, Any}
    )

    specification = Specifications.load(
        basename(path(:specification; prefix = location));
        loader
    )

    assert_compatible_versions(specification)

    locate_definition(experiment, symbol) = repr(
        "text/plain",
        experiment[Symbol("^$symbol")],
    )

    simulations = []
    for (i, experiment) in enumerate(Specifications.unroll(specification))
        model = Models.Model(experiment[:model])
        takes = Simulations.takes(experiment[:take])
        simulation_seed = experiment[:simulation_seed]
        channel = experiment[:channel]
        slices_path = path(:slices, channel; prefix = location)

        simulation = (;
            item = locate_definition(experiment, :item),
            initial = locate_definition(experiment, :initial),
            model = locate_definition(experiment, :model),
            label = experiment[:label],
            seed = experiment[:simulation_seed],
            channel,
            slices = basename(slices_path),
        )
        push!(simulations, simulation)
        @info(
            "About to run simulation '$(simulation.item)'.",
            label = simulation.label,
            model = simulation.model,
            initial = simulation.initial,
            into = simulation.slices,
        )

        transcript = simulate(
            model,
            experiment[:initial],
            takes;
            randomness = randomness(simulation_seed),
        )

        collected = Models.collect(transcript, model)
        slices = (;
            :simulation => fill(i, length(collected.t)),
            collected...,
        )

        if isfile(slices_path)
            Arrow.append(slices_path, slices)
        else
            Arrow.write(slices_path, slices, file = false)
        end
    end
    Arrow.write(
        path(:simulations; prefix = location),
        simulations;
        dictencode = true
    )

    return true
end

function main(;
    location,
    prepare,
    simulate,
    specifications,
    seed,
)
    timestamp = Dates.now()
    location = replace(location, "{TIMESTAMP}" => timestamp)

    if !any([prepare, simulate])
        prepare = true
        simulate = true
    end

    @eval import JSON
    prepare && Base.invokelatest(prepare!; location, specifications, seed)

    @eval using GeneRegulatorySystems
    @eval import Arrow
    simulate && !Base.invokelatest(simulate!; location)
end

end
