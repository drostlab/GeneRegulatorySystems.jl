include("sysimage.jl")
@info "Precompiling command `$SysimageScript`..."
SysimageScript.run([])
redirect_stdout(devnull) do
    SysimageScript.run(["locate"])
end

include("sample.jl")
@info "Precompiling command `$SampleScript`..."
SampleScript.run([])
mktempdir() do sink
    experiment = joinpath(
        @__DIR__() |> dirname |> dirname,
        "examples",
        "complete.experiment.json"
    )
    SampleScript.run(["--sink", "$sink/{TIMESTAMP}/", "--experiment", experiment])
end

@info "Finished executing example workload."
