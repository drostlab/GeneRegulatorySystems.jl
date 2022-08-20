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

include("sample.jl")
include("sysimage.jl")

export Sample, Sysimage

end # module
