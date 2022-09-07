module ExperimentScript

import GeneRegulatorySystemsTools: repository_version, path, Specifications

import Dates
using Random
import SHA

using ArgParse
import Arrow
using ComponentArrays
import GeneRegulatorySystems
import JSON

settings() = @add_arg_table! ArgParseSettings(
    prog = "experiment",
    exit_after_help = false
) begin
    "--location", "-l"
        default = "results/{TIMESTAMP}/"

    "--prepare"
        action = :store_true

    "--seed"
        default = "seed"

    "--simulate"
        action = :store_true

    "specifications"
        nargs = '*'
        arg_type = String
end

randomness(seed::AbstractString) =
    Xoshiro(reinterpret(UInt64, SHA.sha256(seed))...)

columns(xs; genes) = (
    Symbol("$component[$(genes[i])]") => (row -> row[component][i]).(xs)
    for component in keys(first(xs))
    for i in eachindex(first(xs)[component])
)

function map_paths(paths)
    preliminary_map = Dict(p => basename(p) for p in paths)
    if allunique(vcat(path(:specification), values(preliminary_map)...))
        return preliminary_map
    else
        return Dict(p => "_$(i)_$(basename(p))" for (i, p) in enumerate(paths))
    end
end

function confirm_compatible_versions(specification)
    if (specification.bindings[:_julia_version] != "v$VERSION")
        @error(
            "Experiment was prepared with a different Julia version.",
            specification.bindings[:_julia_version],
            "v$VERSION",
        )
        @info "This is disallowed to ensure reproducibility."
        return false
    end

    if (specification.bindings[:_version] != repository_version())
        @error(
            "Experiment was prepared with a different " *
            "GeneRegulatorySystems.jl version.",
            specification.bindings[:_version],
            repository_version(),
        )
        @info "This is disallowed to ensure reproducibility."
        return false
    end

    return true
end

function prepare!(; location, specifications, seed)
    specification_path = path(:specification; prefix = location)
    if ispath(specification_path)
        @error(
            "Cannot prepare experiment, specification already exists.",
            specification_path,
        )
        return false
    elseif isempty(specifications)
        @error "No specifications given to be prepared."
        return false
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
                    :in => length(wrapped) == 1 ? first(wrapped) : wrapped,
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
        return true
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

    confirm_compatible_versions(specification) || return false

    locate_definition(experiment, symbol) = repr(
        "text/plain",
        experiment[Symbol("^$symbol")],
    )

    simulations = []
    for (i, experiment) in enumerate(Specifications.unroll(specification))
        initial = experiment[:initial]
        model = GeneRegulatorySystems.Models.Parameters(experiment[:model])
        takes = GeneRegulatorySystems.Simulations.takes(experiment[:take])
        simulation_seed = experiment[:simulation_seed]
        channel = experiment[:channel]
        trajectories_path = path(:takes, channel; prefix = location)

        simulation = (;
            item = locate_definition(experiment, :item),
            initial = locate_definition(experiment, :initial),
            model = locate_definition(experiment, :model),
            label = experiment[:label],
            seed = experiment[:simulation_seed],
            channel,
            takes = basename(trajectories_path),
        )
        push!(simulations, simulation)
        @info(
            "About to run simulation '$(simulation.item)'.",
            model = simulation.model,
            initial = simulation.initial,
            label = simulation.label,
            takes = simulation.takes,
        )

        transcript = GeneRegulatorySystems.simulate(
            initial,
            model;
            takes,
            randomness = randomness(simulation_seed),
        )

        trajectories = (;
            :simulation => fill(i, length(transcript.ts)),
            :t => transcript.ts,
            columns(transcript.states; model.genes)...,
            columns(transcript.rates; model.genes)...,
        )

        if isfile(trajectories_path)
            Arrow.append(trajectories_path, trajectories)
        else
            Arrow.write(trajectories_path, trajectories, file = false)
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

    if !any((prepare, simulate))
        if isempty(specifications)
            ArgParse.show_help(settings(); exit_when_done = false)
            return 0
        end
        prepare = true
        simulate = true
    end

    if prepare && !prepare!(; location, specifications, seed)
        ArgParse.show_help(settings(); exit_when_done = false)
        return 1
    end

    if simulate && !simulate!(; location)
        ArgParse.show_help(settings(); exit_when_done = false)
        return 1
    end
end

run(arguments = ARGS) = main(;
    @something(
        parse_args(arguments, settings(), as_symbols = true),
        return 1
    )...
)

end # module
