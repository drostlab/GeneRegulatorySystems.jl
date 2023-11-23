"""
Contains all the tools in this package, including the script modules executed
via `./grs`.

The main purpose is to allow precompilation of these modules using
`PackageCompiler`. However, since their very large dependencies (most notably
Makie) slow down loading `GeneRegulatorySystemsTools`, it should normally only
be imported if it is already loaded as part of the current sysimage. Otherwise,
it may be better to load the tools and their dependencies selectively. The
scripts executed via `./grs` do this conditionally, depending on whether
`GeneRegulatorySystemsTools` is already loaded.
"""
module GeneRegulatorySystemsTools

include("common.jl")
include("visualization.jl")

include("experiment/script.jl")
include("experiment/tool.jl")
include("inspect/script.jl")
include("inspect/tool.jl")

end
