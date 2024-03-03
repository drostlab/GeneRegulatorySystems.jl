module Specifications

using Base: Fix2

range_(x) = range(; x...)

constructor(name::AbstractString) = constructor(Symbol(name))
constructor(name::Symbol) = constructor(Val(name))
constructor(::Val{Symbol("")}) = Dict{String, Any}
constructor(::Val{:range}) = range_

abstract type Specification end

struct Slice <: Specification end

function references(s::AbstractString, bound::Set{Symbol})
    found = eachmatch(r"\$\{(\^?\w+)\}", s) .|> first .|> Symbol |> Set
    found ⊆ bound || error("undefined references: ", setdiff(found, bound))
    found
end

function references(x::AbstractDict{Symbol}, bound::Set{Symbol})
    found = mapreduce(
        Fix2(references, bound),
        union,
        values(filter(!=(:$) ∘ first, x)),
        init = Set{Symbol}(),
    )

    if haskey(x, :$)
        direct = Symbol(x[:$] isa AbstractVector ? first(x[:$]) : x[:$])
        found = union(found, Set([direct]))
    end

    found ⊆ bound || error("undefined references: ", setdiff(found, bound))
    found
end

references(xs::AbstractVector, bound::Set{Symbol}) =
    mapreduce(Fix2(references, bound), union, xs, init = Set{Symbol}())

references(_x, _bound::Set{Symbol}) = Set{Symbol}()

@kwdef struct Template <: Specification
    value
    constructor
    free::Set{Symbol}

    Template(value, constructor, free::Set{Symbol}) =
        # TODO: Perhaps we should add a (single element by default, but
        # configurable) cache to Template? This would alleviate the need for
        # this distinction:
        if isempty(free)
            # Eagerly construct the payload since value is already fully
            # closed; this will prevent unnecessary reconstructions down the
            # line for this common case.
            new(constructor(value), identity, free)
        else
            new(value, constructor, free)
        end
end

Template(value; constructor = identity, bound = Set{Symbol}()) =
    Template(free = references(value, bound); value, constructor)

reference(name::Symbol; bound = Set([name])) =
    Template(Dict(:$ => name); bound)

@kwdef struct Scope <: Specification
    definitions::Dict{Symbol, Specification}
    step::Specification = Slice()
    barrier::Bool = false
    branch::Bool = false
    free::Set{Symbol} = union(
        mapreduce(free, union, values(definitions), init = Set{Symbol}()),
        barrier ? Set{Symbol}() : setdiff(free(step), keys(definitions)),
    )
end

abstract type Sequence <: Specification end

@kwdef struct List <: Sequence
    items::Vector{Specification}
    free::Set{Symbol} = mapreduce(free, union, items, init = Set{Symbol}())
end

List(items) = List(; items)

@kwdef struct Each <: Sequence
    items::Template
    as::Symbol = Symbol("")
    step::Specification
    free::Set{Symbol} = union(
        free(items),
        setdiff(free(step), Set(as == Symbol("") ? Symbol[] : [as])),
    )
end

struct Load <: Specification
    path::AbstractString
end

free(::Slice) = Set{Symbol}()
free(::Load) = Set{Symbol}()
free(s::Specification) = s.free

paste(x::AbstractString) = x
paste(x::Number) = repr(x)
paste(::Any) = "__omitted__"

pluck(x, path::AbstractVector) = foldl(pluck, path, init = x)
pluck(x::AbstractDict{Symbol}, key::AbstractString) = pluck(x, Symbol(key))
pluck(x::AbstractDict{Symbol}, key::Symbol) = key == Symbol("") ? x : x[key]
pluck(xs::AbstractVector, key::AbstractString) = pluck(xs, parse(Int, key))
pluck(xs::AbstractVector, i::Int) = xs[i]
pluck(x, key::AbstractString) =
    isempty(key) ? x : getproperty(x, Symbol(key))

function substituted(target::AbstractString; bindings::AbstractDict{Symbol})
    new = replace(
        target,
        ("\${$key}" => paste(value) for (key, value) in bindings)...
    )

    new == target ? nothing : Some(new)
end

substituted(_target; _...) = nothing

function substituted(target::AbstractVector; bindings::AbstractDict{Symbol})
    changed = Dict(
        i => something(value)
        for (i, value) in zip(
            LinearIndices(target),
            substituted.(target; bindings)
        )
        if !isnothing(value)
    )

    isempty(changed) ? nothing : Some([
        get(changed, i, old) for (i, old) in pairs(IndexLinear(), target)
    ])
end

function substituted(
    target::AbstractDict{Symbol};
    bindings::AbstractDict{Symbol},
)
    if haskey(target, :$)
        specializations = filter(!=(:$) ∘ first, target)
        prototype = pluck(bindings, target[:$])  # fail on undefined reference
        if isempty(specializations)
            Some(prototype)
        else
            Some(merge(prototype, substitute(specializations; bindings)))
            #    ^ fail unless template is a Dict
        end
    else
        changed = Dict(
            key => something(value)
            for (key, value) in zip(
                keys(target),
                substituted.(values(target); bindings)
            )
            if !isnothing(value)
        )

        isempty(changed) ? nothing : Some(Dict{Symbol, Any}(
            key => get(changed, key, old) for (key, old) in target
        ))
    end
end

substitute(target; bindings::AbstractDict{Symbol}) =
    something(substituted(target; bindings), Some(target))

function expand(
    template::Template;
    bindings::AbstractDict{Symbol}
)
    bindings = Dict{Symbol, Any}(k => bindings[k] for k in template.free)
    template.constructor(substitute(template.value; bindings))
end

maybe_reference(x::AbstractDict{Symbol}; bound) =
    haskey(x, :$) ? Template(x; bound) : nothing

maybe_load(x::AbstractDict{Symbol}; bound) =
    if haskey(x, :<)
        Scope(
            definitions = Dict{Symbol, Specification}(
                key => Specification(value; bound)
                for (key, value) in x
                if key != :<
            ),
            step = Load(x[:<]),
            barrier = true,
        )
    else
        nothing  # x is not a Load literal
    end

function maybe_tagged_template(x::AbstractDict{Symbol}; bound)
    length(x) == 1 || return
    key, value = only(x)
    m = match(r"\{(?<kind>.*)\}", String(key))
    m !== nothing || return

    Template(value, constructor = constructor(m[:kind]); bound)
end

maybe_range_template(x::AbstractDict{Symbol}; bound) =
    Template(x, constructor = range_; bound)

function maybe_scope(x::AbstractDict{Symbol}; bound)
    isempty(x) && return

    definitions = Dict{Symbol, Specification}(
        key => Specification(value, as = :value; bound)
        for (key, value) in x
        if key != :step && key != :branch
    )
    bound = union(
        bound,
        keys(definitions),
        Set(Symbol("^$k") for k in keys(definitions)),
    )
    step = haskey(x, :step) ? Specification(x[:step]; bound) : Slice()
    branch = get(x, :branch, false)

    Scope(; definitions, step, branch)
end

function maybe_each(x::AbstractDict{Symbol}; bound)
    haskey(x, :each) || return

    definitions = Dict{Symbol, Specification}(
        key => Specification(value, as = :value; bound)
        for (key, value) in x
        if key ∉ [:each, :as, :step, :branch]
    )
    bound = union(
        bound,
        keys(definitions),
        Set(Symbol("^$k") for k in keys(definitions)),
    )
    items = Specification(x[:each], as = :items; bound)

    if haskey(x, :as)
        as = Symbol(x[:as])
        bound = union(bound, [as, Symbol("^$as")])
    else
        as = Symbol("")
    end

    step = haskey(x, :step) ? Specification(x[:step]; bound) : Slice()
    each = Each(; items, as, step)

    if isempty(definitions) && !haskey(x, :branch)
        each  # elide unnecessary Scope
    else
        Scope(step = each, branch = get(x, :branch, false); definitions)
    end
end

Specification(x; bound::Set{Symbol} = Set{Symbol}(), as::Symbol = :step) =
    Specification(x, Val(as); bound)

Specification(value, ::Val; bound::Set{Symbol}) = Template(value; bound)

Specification(xs::AbstractVector, ::Val{:step}; bound::Set{Symbol}) =
    List(items = Specification.(xs; bound))

Specification(
    x::AbstractDict{Symbol},
    ::Val{:value};
    bound::Set{Symbol}
) = @something(
    maybe_reference(x; bound),
    maybe_load(x; bound),
    maybe_tagged_template(x; bound),
    Template(x; bound),
)

Specification(
    x::AbstractDict{Symbol},
    ::Val{:items};
    bound::Set{Symbol}
) = @something(
    maybe_reference(x; bound),
    maybe_tagged_template(x; bound),
    maybe_range_template(x; bound),
    Template(x; bound),
)

Specification(
    x::AbstractDict{Symbol},
    ::Val{:step};
    bound::Set{Symbol}
) = @something(
    maybe_reference(x; bound),
    maybe_load(x; bound),
    maybe_tagged_template(x; bound),
    maybe_each(x; bound),
    maybe_scope(x; bound),
    Slice(),
)

representation(x::Dict) = x
representation(xs::AbstractVector) = representation.(xs)
representation(x::Integer) = x
representation(x::AbstractFloat) = x
representation(x::AbstractString) = x
representation(x::Symbol) = string(x)
representation(x; simple = false, rest...) =
    representation(x, Val(simple); rest...)
function representation(x, ::Val{true}; omit_defaults = Pair{Symbol, Any}[])
    result = Dict{Symbol, Any}(
        key => representation(getproperty(x, key))
        for key in propertynames(x)
    )
    for (key, default) in omit_defaults
        if result[key] == default
            delete!(result, key)
        end
    end
    result
end

end
