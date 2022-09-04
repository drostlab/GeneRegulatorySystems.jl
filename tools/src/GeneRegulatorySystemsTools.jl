module GeneRegulatorySystemsTools

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

path(name, kind::Symbol; prefix = "") = path(name, Val(kind); prefix)
path(name, ::Val{:specification}; prefix) = "$prefix$name.json"
path(name, ::Val{:simulations_result}; prefix) =
    "$prefix$name.simulations.result.json"
path(name, ::Val{:simulations_data}; prefix) =
    "$prefix$name.simulations.stream.arrow"

end # module
