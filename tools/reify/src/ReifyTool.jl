module ReifyTool

include("$(@__DIR__)/../../common.jl")
using .Common: reify, warn_incompatible_versions

import AbstractTrees: AbstractTrees, children
using GeneRegulatorySystems
import JSON

@kwdef struct Representation
    type_::Type
    x
end

maybe_represent(x) =
    try
        Representation(type_ = typeof(x), x = Specifications.representation(x))
    catch
        x
    end

children(r::Representation) = children(r.x)
children(f!::Models.Model) = NamedTuple(
    key => getproperty(f!, key) for key in propertynames(f!)
)
children(f!::Models.Derived) = (;
    definition = maybe_represent(f!.definition),
    f!.model,
)
children(f!::Models.Plumbing.Adjust) = children(f!.adjustment)
children(f!::Schedule) = (; f!.bindings, f!.specification)
children(s::Specifications.Template) =
    isempty(s.free) ? children(s.value) : (s.value,)
children(s::Specifications.Scope) = (; s.definitions, s.step)
children(s::Specifications.List) = s.items
children(s::Specifications.Each) = (; s.items, s.step)

free_suffix(free) =
    if isempty(free)
        ""
    else
        ", free: " * join(sort(collect(free)), ", ")
    end

printnode(io::IO, node; kw...) = print(io, p(node))

p(x) = repr(x)
p(r::Representation) = "$(r.type_), specified by: $(p(r.x))"
p(xs::Tuple) = isempty(xs) ? "()" : "(⋯)"
p(xs::Vector) = isempty(xs) ? "[]" : "[⋯]"
p(x::Dict) = isempty(x) ? "Dict()" : "Dict(⋯)"
p(pair::Pair) = p(first(pair))
p(f!::Models.Model) = f! |> typeof |> nameof |> string
p(f!::Models.Plumbing.Adjust) = "Adjust ($(f!.adjust))"
p(f!::Schedule) = "Schedule\
    $(isempty(f!.path) ? "" : " at $(f!.path)")\
    $(f!.branch ? " (branching)" : "")"
p(s::Specifications.Template) =
    if isempty(s.free)
        p(s.value)
    elseif s.constructor isa typeof(identity)
        "Template$(free_suffix(s.free))"
    else
        "Template ($(typeof(s.constructor)))$(free_suffix(s.free))"
    end
p(s::Specifications.Scope) = "Scope\
    $(s.barrier ? " with barrier" : "")\
    $(s.branch ? " (branching)" : "")\
    $(free_suffix(s.free))"
p(s::Specifications.List) = "List$(free_suffix(s.free))"
p(s::Specifications.Each) =
    "Each$(s.as != Symbol("") ? " as $(s.as)" : "")$(free_suffix(s.free))"
p(s::Specifications.Load) = "Load '$(s.path)'"
p(::Specifications.Slice) = "continuously"
p(l::Scheduling.Locator) = "@$(l.path)"

function main(;
    location,
    path,
    seed,
    representation,
    format,
    maxdepth,
)
    path = something(path, "")
    object =
        if isfile(location)
            reify(location, path; seed)
        else
            warn_incompatible_versions(location)
            reify(path; location, seed)
        end

    if representation
        object = Specifications.representation(object)
    end

    if format == :dump
        dump(object; maxdepth)
    elseif format == :julia
        println(repr(object))
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
