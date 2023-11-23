module Common

using GeneRegulatorySystems

import JSON

import LibGit2

repository_version() = LibGit2.format(
    LibGit2.GitDescribeResult(
        LibGit2.GitRepo(@__DIR__() |> dirname |> dirname)
    );
    options = LibGit2.DescribeFormatOptions(;
        dirty_suffix = Base.unsafe_convert(
            Cstring,
            Base.cconvert(Cstring, "-dirty")
        )
    )
)

artifact(kind::Symbol, name = nothing; prefix = "") =
    "$prefix$(artifact(Val(kind), name))"
artifact(::Val{:specification}, ::Nothing) = "experiment.schedule.json"
artifact(::Val{:index}, ::Nothing) = "index.arrow"
artifact(::Val{:segments}, into) = "segments$into.stream.arrow"

reify(path; location) = Scheduling.reify(
    Schedule(specification = Specifications.Load(
        basename(artifact(:specification, prefix = location))
    )),
    path;
    load = filename -> JSON.parsefile(
        "$(dirname(location))/$filename",
        dicttype = Dict{Symbol, Any},
    )
)

COMPONENT_PATTERN = r"(?<group>.+)\.(?<kind>.+)"

struct TrajectoryComponent
    kind::Symbol
    group::String
end

function TrajectoryComponent(dimension::AbstractString)
    m = match(COMPONENT_PATTERN, dimension)
    TrajectoryComponent(Symbol(m[:kind]), m[:group])
end

end
