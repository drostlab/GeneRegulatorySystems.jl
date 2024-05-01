module ExportTool

include("$(@__DIR__)/../../common.jl")
using .Common: artifact, warn_incompatible_versions

import Arrow
using Chain
import CSV
using DataFrames
import JSON
using PrecompileTools

function load_wide(index; location, kinds, names)
    is = unique(index.i)
    channels = unique(index.into)
    @chain begin
        mapreduce(vcat, channels) do channel
            @chain begin
                "$(dirname(location))/$channel"
                Arrow.Table
                DataFrame
                subset(
                    :i => ByRow(in(is)),
                    :name => ByRow(contains(kinds) ∘ string)
                )
            end
        end
        groupby([order(:i), order(:name)])
        combine(_, valuecols(_) .=> last .=> valuecols(_))
        unstack(:i, :name, :value)
        select(:i => ByRow(i -> names[i]) => :name, Not(:i))
        permutedims(:name)
        sort!(:name)
    end
end

function main(;
    location,
    sink,
    format,
    path,
    model,
    label,
    events,
    kinds,
    dry
)
    warn_incompatible_versions(location)

    path = [Regex("^\\Q$prefix\\E(?=[/+-]|\$)") for prefix in path]
    model = [Regex("^\\Q$prefix\\E(?=[/+-]|\$)") for prefix in model]
    criteria = Dict{Symbol, Base.Callable}(
        column => ByRow(x -> any(contains(x, r) for r in rs))
        for (column, rs) in [
            (:path, path)
            (:model, model)
            (:label, label)
            (:into, events)
        ]
        if !isempty(rs)
    )

    index = @chain begin
        artifact(:index; prefix = location)
        Arrow.Table
        DataFrame
        subset(:count => ByRow(>(0)))
        subset(criteria...)
    end

    if dry
        @show select(
            index,
            :i,
            :path,
            :to => :at,
            :model,
            :label,
            :count,
            :into => :events,
        )
        return nothing
    end

    names = Dict(
        segment.i => "\
            $(isempty(segment.label) ? "unlabeled" : segment.label)\
            -$(segment.to)\
        "
        for segment in eachrow(index)
    )
    if !allunique(values(names))
        @warn "Slice labels are not unique, dropping labels..."
        names = Dict(
            segment.i => "unlabeled-$(segment.i)-$(segment.to)"
            for segment in eachrow(index)
        )
    end
    result = load_wide(index; location, kinds, names)

    if format === nothing
        if sink === nothing
            format = :csv
        else
            _, extension = splitext(sink)
            if startswith(extension, '.')
                format = Symbol(extension[2:end])
            end
        end
    end

    if format == :arrow
        if sink === nothing
            @error "Refusing to write Arrow to standard output."
            @info "Either provide `sink` or use another format."
            throw(:help)
        end
        Arrow.write(sink, result)
    elseif format == :csv
        CSV.write(something(sink, stdout), result)
    elseif format == :tsv
        CSV.write(something(sink, stdout), result, delim = '\t')
    else
        @error "Cannot export to unknown format `$format`."
        throw(:help)
    end

    nothing
end

@setup_workload begin
    get(ENV, "JULIA_PKG_PRECOMPILE_AUTO", "1") == "0" &&
        error("Precompilation triggered implicitly; this should not happen.")

    mktempdir() do location
        Arrow.write(
            artifact(:index, prefix = location),
            DataFrame(
                i = 1:3,
                path = ["-1", "-1", "-2"],
                from = [0.0, 1.0, 1.0],
                to = [0.0, 1.0, 2.0],
                model = ["-1", "-1", "-2"],
                label = ["A", "B", "C"],
                count = [2, 2, 1],
                into = fill(
                    basename(artifact(:events, "-1", prefix = location)),
                    3,
                ),
            )
        )

        Arrow.write(
            artifact(:events, "-1", prefix = location),
            DataFrame(
                i = [1, 1, 2, 2, 3],
                t = [0.0, 0.0, 1.0, 1.0, 1.5],
                name = [
                    Symbol("1.mrnas"),
                    Symbol("1.proteins"),
                    Symbol("1.mrnas"),
                    Symbol("1.proteins"),
                    Symbol("2.active"),
                ],
                value = [1, 0, 2, 1, 1],
            )
        )

        write(artifact(:specification, prefix = location), "[]")

        @compile_workload begin
            main(;
                location,
                sink = "$location/export.csv",
                format = nothing,
                path = String[],
                model = String[],
                label = Regex[],
                events = Regex[],
                kinds = r"",
                dry = false,
            )
            main(;
                location,
                sink = "$location/export.arrow",
                format = nothing,
                path = String[],
                model = String[],
                label = Regex[],
                events = Regex[],
                kinds = r"",
                dry = false,
            )
        end
    end
end

end
