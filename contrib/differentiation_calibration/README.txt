To regenerate the parameters used in `Differentiation.proportion_rate` and
`Differentiation.timing_factor`, you will need Matlab installed. Follow these
instructions:


For timing:

1. Run:

    tools/grs experiment \
        contrib/differentiation_calibration/timing.schedule.json

2. Convert the resulting events stream to wide CSV format, and place it in the
   results directory. E.g. in Julia:

    import Arrow
    import CSV
    using DataFrames
    d = "⟨path-to-events.stream.arrow⟩" |> Arrow.Table |> DataFrames
    CSV.write("⟨path-to-events.csv⟩", unstack(d, :name, :value))

3. In this directory (contrib/differentiation_calibration), run:

    ⟨path-to-Matlab⟩ -nodisplay -r "timing_fit('⟨path-to-results⟩'); exit"


For proportion:

1. Run:

    tools/grs experiment \
        contrib/differentiation_calibration/proportion.schedule.json

2. Convert the resulting events stream to wide CSV format. (See above.)

3. In this directory, run:

    ⟨path-to-Matlab⟩ -nodisplay -r "proportion_fit('⟨path-to-results⟩'); exit"


The parameters currently in use can be obtained using Julia version 1.10.1 at
commit a2f355fe585598a945d144e9c8e955fd23ac1eb8.
