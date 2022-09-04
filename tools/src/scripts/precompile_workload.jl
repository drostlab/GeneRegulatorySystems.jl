include("sysimage.jl")
@info "Precompiling command `$SysimageScript`..."
SysimageScript.run([])
redirect_stdout(devnull) do
    SysimageScript.run(["locate"])
end

include("simulate.jl")
@info "Precompiling command `$SimulateScript`..."
SimulateScript.run([])
mktempdir() do location
    experiment = joinpath(
        @__DIR__() |> dirname |> dirname,
        "examples",
        "complete.experiment.json"
    )
    SimulateScript.run([
        "--location",
        "$location/{TIMESTAMP}/",
        "--experiment",
        experiment
    ])
end

@info "Finished executing example workload."
