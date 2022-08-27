module SimulateScript

import GeneRegulatorySystemsTools: repository_version, path

import Dates
import Pkg
using Random

using ArgParse
import Arrow
using ComponentArrays
import GeneRegulatorySystems
import JSON

settings() = @add_arg_table! ArgParseSettings(
    prog = "simulate",
    exit_after_help = false
) begin
    "--location", "-l"
        default = "results/{TIMESTAMP}/"

    "--experiment", "-e"
        action = :append_arg
        arg_type = String
        dest_name = "experiments"
        metavar = "EXPERIMENT"

    "more_experiments"
        nargs = '*'
        arg_type = String
        metavar = "EXPERIMENT"
end

derive_seed(seed, i) = seed + i

columns(xs) = (
    Symbol(label) => getindex.(xs, i)
    for (i, label) in zip(LinearIndices(first(xs)), labels(first(xs)))
)

function main(;
    experiments,
    more_experiments,
    location,
)
    append!(experiments, more_experiments)
    if isempty(experiments)
        ArgParse.show_help(settings(); exit_when_done = false)
        return
    end

    timestamp = Dates.now()
    location = replace(location, "{TIMESTAMP}" => timestamp)

    mkpath(dirname(location))

    for experiment in experiments
        specification = JSON.parsefile(
            experiment;
            dicttype = Dict{Symbol, Any}
        )
        name = @something(
            get(specification, :name, nothing),
            experiment |> basename |> splitext |> first
        )
        specification_location = path(name, :specification; prefix = location)
        cp(experiment, specification_location)
        seed = get(specification, :seed, 1)
        model = GeneRegulatorySystems.Models.load(specification[:model])
        simulations = specification[:simulations]

        @info(
            "About to run '$name'",
            typeof(model),
            simulations = length(simulations),
            seed,
            see = path(name, :simulations_result; prefix = location)
        )
        data_location = path(name, :simulations_data; prefix = location)
        for (i, simulation) in enumerate(simulations)
            initial = @something(
                get(simulation, :initial, nothing),
                get(specification, :initial, nothing),
                Dict{Symbol}()
            )
            simulation_seed = @something(
                get(simulation, :seed, nothing),
                derive_seed(seed, i)
            )
            transcript = GeneRegulatorySystems.simulate(
                initial,
                model;
                takes = simulation[:take],
                randomness = MersenneTwister(simulation_seed)
            )
            result = (;
                :simulation => fill(i, length(transcript.ts)),
                :t => transcript.ts,
                columns(transcript.states)...,
                columns(transcript.rates)...,
            )
            if i == 1
                Arrow.write(data_location, result, file = false)
            else
                Arrow.append(data_location, result)
            end
        end

        open(path(name, :simulations_result; prefix = location), "w") do file
            JSON.print(
                file,
                Dict(
                    :timestamp => timestamp,
                    :specification => basename(specification_location),
                    :simulations => basename(data_location),
                    :seed => seed,
                    :version => repository_version(),
                ),
                4,
            )
        end
    end
end

run(arguments = ARGS) = main(;
    @something(
        parse_args(arguments, settings(), as_symbols = true),
        return
    )...
)

end # module
