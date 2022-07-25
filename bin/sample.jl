import Dates
import Pkg
using Random

using ArgParse
using ComponentArrays
import Arrow
import JSON
import GeneRegulatorySystems

settings = @add_arg_table! ArgParseSettings() begin
    "--experiment", "-e"
        action = :append_arg
        arg_type = String
        dest_name = "experiments"
        metavar = "EXPRERIMENT"
    
    "--sink", "-s"
        default = "results/{TIMESTAMP}"

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
    timestamp = Dates.now()
    sink = replace(sink, "{TIMESTAMP}" => timestamp)

    mkpath(sink)
    manifest = cp(
        joinpath(Pkg.project().path |> dirname, "Manifest.toml"),
        joinpath(sink, "$timestamp.manifest.toml")
    )

    for experiment in experiments
        specification = JSON.parsefile(experiment; dicttype = Dict{Symbol, Any})
        name = @something(
            get(specification, :name, nothing),
            experiment |> basename |> splitext |> first
        )
        cp(experiment, joinpath(sink, "$name.json"), force = true)
        seed = get(specification, :seed, 1)
        model = GeneRegulatorySystems.Models.load(specification[:model])
        simulations = specification[:simulations]

        @info "About to run '$name'" typeof(model) simulations=length(simulations) seed see=joinpath(sink, "$name.report.json")
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
                Arrow.write(joinpath(sink, "$name.sample.arrow"), result, file = false)
            else
                Arrow.append(joinpath(sink, "$name.sample.arrow"), result)
            end
        end

        open(joinpath(sink, "$name.report.json"), "w") do file
            JSON.print(
                file,
                Dict(
                    :timestamp => timestamp,
                    :experiment => "$name.json",
                    :sample => "$name.sample.arrow",
                    :seed => seed,
                    :environment => manifest,
                ),
                4,
            )
        end
    end
end

main(; parse_args(settings, as_symbols = true)...)