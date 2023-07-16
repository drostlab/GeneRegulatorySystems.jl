module Conversion

cast(::Type{T}, x::T; _...) where {T} = x
cast(T::Type, x::AbstractDict{Symbol}, ::Val{K}; context) where {K} =
    cast(fieldtype(T, K), x[K]; context)
cast(::Type{Symbol}, x; _...) = Symbol(x)
cast(T::Type{<:Real}, x::Real; _...) = convert(T, x)
cast(T::Type{<:Real}, x::AbstractString; _...) = parse(T, x)
cast(::Type{Vector{T}}, xs::Vector{T}; _...) where {T} = xs
cast(::Type{Vector{T}}, xs::AbstractVector; context = nothing) where {T} =
    cast.(T, xs; context)
cast(T::Type, x::AbstractDict{Symbol}; context = x) = T(; (
    key => cast(T, x, Val(key); context)
    for key in keys(x)
    if hasfield(T, key)
)...)
cast(::Type{Union{Some{T}, Nothing}}, ::Nothing; _...) where {T} = nothing
cast(::Type{Union{Some{T}, Nothing}}, x; context) where {T} =
    Some(cast(T, x; context))
cast(  # disambiguation
    ::Type{Union{Some{T}, Nothing}},
    x::AbstractDict{Symbol};
    context,
) where {T} = Some(cast(T, x; context))

end
