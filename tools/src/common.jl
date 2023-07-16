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

artifact(kind::Symbol, name = nothing; prefix = "") =
    "$prefix$(artifact(Val(kind), name))"
artifact(::Val{:specification}, ::Nothing) = "specification.json"
artifact(::Val{:index}, ::Nothing) = "index.arrow"
artifact(::Val{:segments}, into) = "segments$into.stream.arrow"

end
