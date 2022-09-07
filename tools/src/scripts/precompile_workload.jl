include("sysimage.jl")
@info "Precompiling command `$SysimageScript`..."
SysimageScript.run([])
redirect_stdout(devnull) do
    SysimageScript.run(["locate"])
end

include("experiment.jl")
@info "Precompiling command `$ExperimentScript`..."
ExperimentScript.run([])
experiment_path(name) = joinpath(
    @__DIR__() |> dirname |> dirname,
    "examples",
    name
)
mktempdir() do location
    experiments = experiment_path.([
        "complete.experiment.json",
        "templating.experiment.json",
        "channels.experiment.json",
    ])
    ExperimentScript.run([
        "--location",
        "$location/{TIMESTAMP}/",
        experiments...,
    ])
end

@info "Finished executing example workload."
