import Dates

import GeneRegulatorySystemsTools: ExperimentScript, InspectScript

mktempdir() do location
    result_location = "$location/$(Dates.now())/"

    @info "Precompiling command `$ExperimentScript`..."
    ExperimentScript.run([])
    ExperimentScript.run([
        "--location",
        result_location,
        joinpath(@__DIR__, "precompile_experiment.json"),
    ])

    @info "Precompiling command `$InspectScript`..."
    InspectScript.run(["--help"])
    @info "This step may take a couple of minutes..."
    @info "(Empty windows will open briefly, do not close them manually.)"
    InspectScript.run(["--no-wait-for-close", result_location])
    InspectScript.run([
        "--label-pattern",
        "initial-.*-t200",
        "--no-wait-for-close",
        "--kinds",
        "promoters,mrnas,log10(proteins)",
        result_location,
    ])
end

@info "Finished executing example workload."
