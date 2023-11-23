import Dates

import GeneRegulatorySystemsTools: ExperimentScript, InspectScript

mktempdir() do location
    result_location = "$location/$(Dates.now())/"

    @info "Precompiling command `$ExperimentScript`..."
    ExperimentScript.run([])
    ExperimentScript.run([
        "--location",
        result_location,
        joinpath(@__DIR__, "precompile.schedule.json"),
    ])

    @info "Precompiling command `$InspectScript`..."
    InspectScript.run(["--help"])
    @info "This step may take a couple of minutes..."
    @info "(Empty windows will open briefly, do not close them manually.)"
    InspectScript.run(["--no-wait-for-close", result_location])
    InspectScript.run([
        "--label-pattern",
        "default-initial-.*-at200",
        "--no-wait-for-close",
        "--kinds",
        "promoter,mrnas,log10(proteins)",
        result_location,
    ])
    InspectScript.run([
        "--label-pattern",
        "default-initial-.*-to200",
        "--no-wait-for-close",
        "--kinds",
        "promoter,mrnas,log10(proteins)",
        result_location,
    ])
end

@info "Finished executing example workload."
