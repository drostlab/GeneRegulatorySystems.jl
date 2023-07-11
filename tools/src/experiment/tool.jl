module ExperimentTool

if nameof(parentmodule(@__MODULE__)) == :GeneRegulatorySystemsTools
    @eval using GeneRegulatorySystemsTools: Common
else
    include("$(@__DIR__)/../common.jl")
end

using .Common: repository_version, path

import Dates

using Chain

# NOTE: This module lazily imports additional modules in `main`.

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
                        :simulation_seed => raw"$seed-simulation-$^item",
                        :extraction_seed => raw"$seed-extraction-$^item",
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

function load_specification(location)
    loader(path) = JSON.parsefile(
        "$(dirname(location))/$path";
        dicttype = Dict{Symbol, Any}
    )

    specification = Specifications.load(
        basename(path(:specification; prefix = location));
        loader
    )

    assert_compatible_versions(specification)

    specification
end

function simulate!(specification; location)
    simulations = []
    for (i, experiment) in enumerate(Experiments.experiments(specification))
        slices_path = path(:slices, experiment.channel; prefix = location)
        simulation = (;
            item = Experiments.locate_definition(experiment, :item),
            initial = Experiments.locate_definition(experiment, :initial),
            model = Experiments.locate_definition(experiment, :model),
            experiment.label,
            seed = experiment.simulation_seed,
            experiment.channel,
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
            experiment.model,
            experiment.initial,
            experiment.takes;
            randomness = GeneRegulatorySystems.randomness(
                experiment.simulation_seed
            ),
        )

        collected = Models.collect(transcript, experiment.model)
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
end

function extract!(specification; location)
    result = Dict()
    for (i, experiment) in enumerate(Experiments.experiments(specification))
        slices = @chain :slices begin
            path(experiment.channel; prefix = location)
            Arrow.Table
            DataFrame

            subset(:simulation => ByRow(==(i)), view = true)
            select(
                _,
                :simulation,
                :t,
                findall(column -> eltype(column) <: Int, eachcol(_))
            )
        end

        randomness =
            GeneRegulatorySystems.randomness(experiment.extraction_seed)

        for take in experiment.takes
            slice = only(subset(slices, :t => ByRow(==(take.to))))
            extracted =
                experiment.extract(slice[Not([:t, :simulation])]; randomness)
            entry = (;
                slice.simulation,
                slice.t,
                (
                    key => extracted[key]
                    for key in keys(slice)
                    if haskey(extracted, key)
                )...
            )
            channel = get!(result, experiment.channel, typeof(entry)[])
            push!(channel, entry)
        end
    end

    for (channel, entries) in result
        Arrow.write(
            path(:extracts, channel; prefix = location),
            entries;
            dictencode = true,
        )
    end
end

function main(;
    location,
    prepare,
    simulate,
    extract,
    specifications,
    seed,
)
    timestamp = Dates.now()
    location = replace(location, "{TIMESTAMP}" => timestamp)

    if !any([prepare, simulate, extract])
        prepare = true
        simulate = true
        extract = true
    end

    @eval import JSON
    prepare && Base.invokelatest(prepare!; location, specifications, seed)

    @eval using GeneRegulatorySystems
    specification = Base.invokelatest(load_specification, location)

    @eval import Arrow
    simulate && Base.invokelatest(simulate!, specification; location)

    @eval using DataFrames
    extract && Base.invokelatest(extract!, specification; location)

    nothing
end

end
