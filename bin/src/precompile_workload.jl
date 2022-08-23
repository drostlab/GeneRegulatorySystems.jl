using GeneRegulatorySystemsTools

@info "Precompiling command `$Sysimage`..."
Sysimage.run([])
redirect_stdout(devnull) do
    Sysimage.run(["locate"])
end

@info "Precompiling command `$Sample`..."
Sample.run([])
mktempdir() do sink
    experiment = joinpath(
        @__DIR__() |> dirname |> dirname,
        "examples",
        "complete.experiment.json"
    )
    Sample.run(["--sink", "$sink/", "--experiment", experiment])
end

@info "Finished executing example workload."
