module Specifications

abstract type Specification end

struct Item <: Specification end

Base.@kwdef struct Items <: Specification
    specifications::Vector{Specification}
end

Base.@kwdef struct Let <: Specification
    bindings::Dict{Symbol}
    template::Specification
end

Base.@kwdef struct Each <: Specification
    iterable::AbstractVector
    variable::Union{Symbol, Nothing} = nothing
    template::Specification = Item()
end

Base.@kwdef struct Load <: Specification
    path::AbstractString
end

iterable(xs::AbstractVector) = xs
iterable(xs::AbstractDict{Symbol}) = range(; xs...)

Specification(::Nothing) = Item()
Specification(specification::AbstractVector) =
    Items(Specification.(specification))
Specification(specification::AbstractDict{Symbol}) =
    if isempty(specification)
        Item()
    elseif haskey(specification, :<)
        Load(; path = specification[:<])
    elseif haskey(specification, :each)
        variable = get(specification, :as, nothing)
        inner = Each(;
            iterable = iterable(specification[:each]),
            variable = isnothing(variable) ? nothing : Symbol(variable),
            template = Specification(get(specification, :in, nothing)),
        )
        bindings = Dict{Symbol, Any}(
            pair for pair ∈ specification if pair.first ∉ (:each, :as, :in)
        )

        # As a convenience, if there are bindings we introduce an implicit
        # scope for them. Otherwise we can emit the Each as is.
        isempty(bindings) ? inner : Let(; bindings, template = inner)
    else
        # At this point, either there are bindings so we introduce a scope even
        # if :in is missing (and therefore implied), or :in is explicitly
        # specificed so we introduce a scope (even without bindings).
        Let(;
            bindings = Dict{Symbol, Any}(
                pair for pair ∈ specification if pair.first ≠ :in
            ),
            template = Specification(get(specification, :in, nothing)),
        )
    end

load(path::AbstractString; loader::Function) = load(Load(; path); loader)
load(item::Item; loader::Function) = item
load(items::Items; loader::Function) =
    Items(load.(items.specifications; loader))
load(let_::Let; loader::Function) = Let(;
    let_.bindings,
    template = load(let_.template; loader)
)
load(each::Each; loader::Function) = Each(;
    each.iterable,
    each.variable,
    template = load(each.template; loader)
)
load(load_::Load; loader::Function) =
    load(Specification(loader(load_.path)); loader)

struct Locator
    path::Vector{Int}
end

const LOCATOR_PATTERN = r"@(?<path>[/\d]*)"

function Base.show(io::IO, ::MIME"text/plain", locator::Locator)
    segments = (s > 0 ? "/$s" : "/" for s in locator.path)
    write(io, "@$(join(segments))")
end

function Base.parse(::Type{Locator}, locator::AbstractString)
    segments = split(match(LOCATOR_PATTERN, locator)[:path], '/')
    Locator([isempty(s) ? 0 : parse(Int, s) for s in segments][2:end])
end

paste(x::AbstractString) = x
paste(x::Number) = repr(x)
paste(x::Locator) = join(filter(>(0), x.path), "-")
paste(::Any) = "__omitted__"

substituted(::Any; context::AbstractDict{Symbol}) = nothing

function substituted(target::AbstractString; context::AbstractDict{Symbol})
    new = replace(
        target,
        ("\$$key" => paste(value) for (key, value) in context)...
    )
    if new == target
        nothing
    else
        Some(new)
    end
end

function substituted(target::AbstractVector; context::AbstractDict{Symbol})
    changed = Dict(
        i => something(value)
        for (i, value) in zip(
            LinearIndices(target),
            substituted.(target; context)
        )
        if !isnothing(value)
    )
    if isempty(changed)
        nothing
    else
        Some([
            get(changed, i, old) for (i, old) in pairs(IndexLinear(), target)
        ])
    end
end

function substituted(
    target::AbstractDict{Symbol};
    context::AbstractDict{Symbol},
)
    if haskey(target, :$)
        Some(context[Symbol(target[:$])])  # fail if reference is undefined
    else
        changed = Dict(
            key => something(value)
            for (key, value) in zip(
                keys(target),
                substituted.(values(target); context)
            )
            if !isnothing(value)
        )
        if isempty(changed)
            nothing
        else
            Some(Dict{Symbol, Any}(
                key => get(changed, key, old) for (key, old) in target
            ))
        end
    end
end

substitute(target; context::AbstractDict{Symbol}) =
    something(substituted(target; context), target)

function expand(
    context::AbstractDict{Symbol};
    definitions::AbstractDict{Symbol},
    path::AbstractVector{Int} = Int[],
    shadow::Bool = false,
)
    definitions =
        if shadow
            definitions
        else
            filter(definitions) do (name, _)
                !haskey(context, name)
            end
        end
    if isempty(definitions)
        context
    else
        merge(
            context,
            substitute(definitions; context),
            Dict(
                Symbol("^$name") => Locator(path)
                for (name, _) in definitions
            ),
        )
    end
end

Base.eachindex(items::Items) = LinearIndices(items.specifications)
Base.eachindex(each::Each) = LinearIndices(each.iterable)
Base.eachindex(::Let) = 0:0

Base.getindex(items::Items, index) = items.specifications[index]
Base.getindex(each::Each, _index) = each.template
Base.getindex(let_::Let, _index) = let_.template

bindings(::Items, _index) = Dict{Symbol, Any}()
bindings(each::Each, index) =
    if isnothing(each.variable)
        Dict{Symbol, Any}()
    else
        Dict(Symbol(each.variable) => each.iterable[index])
    end
bindings(let_::Let, _index) = let_.bindings

function reify(
    specification::Specification,
    locator::Locator;
    context::AbstractDict{Symbol} = Dict{Symbol, Any}(),
)
    for (i, index) in enumerate(locator.path)
        context = expand(
            context;
            definitions = bindings(specification, index),
            path = locator.path[1:i],
            shadow = true,
        )
        specification = specification[index]
    end

    if specification isa Item
        context = expand(
            context;
            definitions = Dict(:item => nothing),
            locator.path,
            shadow = true,
        )

        if haskey(context, :_defaults)
            context = expand(
                context;
                definitions = context[:_defaults],
                locator.path
            )
        end
    end

    context
end

unroll(
    specification::Specification;
    context::AbstractDict{Symbol} = Dict{Symbol, Any}(),
    path::AbstractVector{Int} = Int[],
) = Channel() do channel
    unroll!(channel, specification; context, path)
end

function unroll!(
    channel,
    ::Item;
    context::AbstractDict{Symbol},
    path::AbstractVector{Int},
)
    context = expand(
        context;
        definitions = Dict(:item => nothing),
        path,
        shadow = true,
    )

    if haskey(context, :_defaults)
        context = expand(
            context;
            definitions = context[:_defaults],
            path,
        )
    end

    push!(channel, context)
end

function unroll!(
    channel,
    specification::Specification;
    context::AbstractDict{Symbol},
    path::AbstractVector{Int},
)
    for index in eachindex(specification)
        subpath = vcat(path, index)
        unroll!(
            channel,
            specification[index];
            context = expand(
                context;
                definitions = bindings(specification, index),
                path = subpath,
                shadow = true,
            ),
            path = subpath,
        )
    end
end

end # module
