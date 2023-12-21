module Common

using GeneRegulatorySystems

import JSON

import LibGit2

repository_version() = LibGit2.format(
    LibGit2.GitDescribeResult(
        LibGit2.GitRepo(@__DIR__() |> dirname)
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
artifact(::Val{:events}, into) = "events$into.stream.arrow"

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

COMPONENT_GROUP_PATTERN = r"(?<group>.+)\.(?<kind>.+)"

struct Dimension
    kind::Symbol
    group::String
end

function Dimension(name::AbstractString)
    m = match(COMPONENT_GROUP_PATTERN, name)
    if m === nothing
        Dimension(Symbol(name), "")
    else
        Dimension(Symbol(m[:kind]), m[:group])
    end
end

Dimension(name::Symbol) = Dimension(String(name))

end
