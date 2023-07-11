module Common

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

path(kind::Symbol, name = nothing; prefix = "") =
    "$prefix$(filename(Val(kind), name))"

filename(::Val{:specification}, ::Nothing) = "specification.json"
filename(::Val{:simulations}, ::Nothing) = "simulations.arrow"
filename(::Val{:slices}, channel) =
    "slices$(isempty(channel) ? "" : "-$channel").stream.arrow"
filename(::Val{:extracts}, channel) =
    "extracts$(isempty(channel) ? "" : "-$channel").arrow"

end
