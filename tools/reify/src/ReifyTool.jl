module ReifyTool

include("$(@__DIR__)/../../common.jl")
using .Common: reify, warn_incompatible_versions

import AbstractTrees
using GeneRegulatorySystems
import JSON

printnode(io::IO, node; kw...) = AbstractTrees.printnode(io, node, kw...)
printnode(io::IO, node::Dict; _...) = print(io, "{}")
printnode(io::IO, node::Vector; _...) = print(io, "[]")

function main(;
    location,
    path,
    representation,
    format,
    maxdepth,
)
    warn_incompatible_versions(location)

    object = reify(something(path, ""); location)
    if representation
        object = Specifications.representation(object)
    end

    if format == :dump
        dump(object; maxdepth)
    elseif format == :json
        JSON.print(object, 4)
    elseif format == :tree
        AbstractTrees.print_tree(printnode, stdout, object; maxdepth)
    else
        @error "Unknown format" format
    end

    nothing
end

end
