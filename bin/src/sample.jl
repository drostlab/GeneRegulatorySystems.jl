module Sample

import ..GeneRegulatorySystemsTools

import Dates
import Pkg
using Random

using ArgParse
import Arrow
using ComponentArrays
import GeneRegulatorySystems
import JSON

settings() = @add_arg_table! ArgParseSettings() begin
    "--experiment", "-e"
        action = :append_arg
        arg_type = String
        dest_name = "experiments"
        metavar = "EXPRERIMENT"
    
    "--sink", "-s"
        default = "results/{TIMESTAMP}/"

    "more_experiments"
        nargs = '*'
        arg_type = String
end

derive_seed(seed, i) = seed + i

columns(xs) = (
    Symbol(label) => getindex.(xs, i)
    for (i, label) in zip(LinearIndices(first(xs)), labels(first(xs)))
)

function main(;
    experiments,
    more_experiments,
    sink,
)
    append!(experiments, more_experiments)
    isempty(experiments) && ArgParse.show_help(settings())

    timestamp = Dates.now()
    sink = replace(sink, "{TIMESTAMP}" => timestamp)

    mkpath(dirname(sink))
    cp(
        joinpath(Pkg.project().path |> dirname, "Manifest.toml"),
        string(sink, "Manifest.toml")
    )

    for experiment in experiments
        specification = JSON.parsefile(experiment; dicttype = Dict{Symbol, Any})
        name = @something(
            get(specification, :name, nothing),
            experiment |> basename |> splitext |> first
        )
        cp(experiment, string(sink, "$name.json"))
        seed = get(specification, :seed, 1)
        model = GeneRegulatorySystems.Models.load(specification[:model])
        simulations = specification[:simulations]

        @info "About to run '$name'" typeof(model) simulations=length(simulations) seed see=string(sink, "$name.result.json")
        for (i, simulation) in enumerate(simulations)
            tag = get(simulation, :tag, nothing)
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
                Arrow.write(string(sink, "$name.sample.arrow"), result, file = false)
            else
                Arrow.append(string(sink, "$name.sample.arrow"), result)
            end
        end

        open(string(sink, "$name.result.json"), "w") do file
            JSON.print(
                file,
                Dict(
                    :timestamp => timestamp,
                    :experiment => string(basename(sink), "$name.json"),
                    :sample => string(basename(sink), "$name.sample.arrow"),
                    :seed => seed,
                    :version => GeneRegulatorySystemsTools.repository_version(),
                    :environment => string(basename(sink), "Manifest.toml"),
                ),
                4,
            )
        end
    end
end

run(arguments = ARGS) = main(;
    parse_args(arguments, settings(), as_symbols = true)...
)

end # module
