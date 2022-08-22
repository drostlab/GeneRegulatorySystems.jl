using GeneRegulatorySystemsTools

redirect_stdout(devnull) do
    Sysimage.run(["invocation"])
end

mktempdir() do sink
    experiment = joinpath(
        @__DIR__() |> dirname |> dirname,
        "examples",
        "complete.experiment.json"
    )
    Sample.run(["--sink", "$sink/", "--experiment", experiment])
end
