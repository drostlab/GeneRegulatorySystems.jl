module NetworkRepresentation

using Catalyst
using ModelingToolkit

using ..V1
using ..Differentiation
using ..KroneckerNetworks
using ..RandomDifferentiation
using ..Scheduling: Primitive
using ..SciML: normalize_name
using ..Specifications
using ..Models
using ..Models: Wrapped, Instant

# TODO: move each method to the model module it belongs to


# TODO: maybe we can represent reaction nodes as hyperlinks instead of nodes? think that would make more sense?
@kwdef struct Link
    kind::Symbol
    from::Symbol
    to::Symbol
    properties::Dict{Symbol, Any} = Dict{Symbol, Any}()
end
#kinds: substrate, product, activation, repression, proteolysis, next, alternative

@kwdef struct Entity
    kind::Symbol
    name::Symbol
    properties::Dict{Symbol, Any} = Dict{Symbol, Any}()
    nodes::Vector{Entity} = Entity[]
    links::Vector{Link} = Link[]
end
#kinds: species, reaction, reaction_system, gene, v1_model, differentiation_core, kronecker_network

function node_lookup(entity::Entity)::Dict{Symbol, Entity}
    Dict(node.name => node for node in entity.nodes)
end

function strip_time(s::Symbol)
    return Symbol(replace(String(s), r"\(t\)$" => ""))
end

struct SpeciesId
    name::Symbol
end

function SpeciesId(s::SymbolicUtils.BasicSymbolic)
    SpeciesId(normalize_name(strip_time(Symbol(s))))
end

function species_components(name::Symbol)
    parts = split(String(name), '.')
    if length(parts) == 1
        return (parent=nothing, species_type=parts[1])
    else
        return (parent=Symbol(parts[1]), species_type=parts[2])
    end
end

parent(name::Symbol) = species_components(name).parent

entity(species::SpeciesId) = let comps = species_components(species.name)
    Entity(
        kind=:species,
        name=species.name,
        properties=Dict(:species_type => comps.species_type)
    )
end

function entity(rs::ReactionSystem)
    nodes = [entity(SpeciesId(s)) for s in Catalyst.species(rs)]
    links = Link[]

    for (i, rxn) in enumerate(Catalyst.reactions(rs))
        # ? maybe we could retrieve the names from the gene cascades or annotate the reactions before building the model somehow?
        # ! also the rxn.rate is basically an equation that depends on the symbol values
        # here if we wanted to display the actual numerical values for a given state of the simulation
        # we would have to either compute them on the frontend side from the equations
        # or ask the server to compute them for us.
        rxn_name = Symbol("rxn$i")
        push!(nodes, Entity(kind=:reaction, name=rxn_name, properties=Dict(:rate => Symbol(rxn.rate))))

        append!(links,
            [Link(kind=:substrate, from=SpeciesId(s).name, to=rxn_name, properties=Dict(:stoich => rxn.substoich[i]))
             for (i,s) in enumerate(rxn.substrates)]
        )
        append!(links,
            [Link(kind=:product, from=rxn_name, to=SpeciesId(p).name, properties=Dict(:stoich => rxn.prodstoich[i]))
             for (i,p) in enumerate(rxn.products)]
        )
    end

    Entity(kind=:reaction_system,
           name=:reaction_system,
           nodes=nodes,
           links=links)
end

function _genes_from_reaction_network(rs_network::Entity)::Tuple{Vector{Entity}, Vector{Entity}, Vector{Link}}

    species_nodes = [n for n in rs_network.nodes if n.kind == :species]
    reaction_nodes = [n for n in rs_network.nodes if n.kind == :reaction]

    parent_dict = Dict(s.name => parent(s.name) for s in species_nodes)

    links_by_to = Dict{Symbol, Vector{Link}}()
    links_by_from = Dict{Symbol, Vector{Link}}()
    for link in rs_network.links
        push!(get!(links_by_to, link.to, Link[]), link)
        push!(get!(links_by_from, link.from, Link[]), link)
    end

    for r in reaction_nodes
        connected_parents = Set(parent_dict[link.from] for link in get(links_by_to, r.name, Link[]) if !isnothing(parent_dict[link.from]))
        union!(connected_parents, Set(parent_dict[link.to] for link in get(links_by_from, r.name, Link[]) if !isnothing(parent_dict[link.to])))
        parent_dict[r.name] = length(connected_parents) == 1 ? first(connected_parents) : nothing
    end

    nodes_by_parent = Dict{Union{Symbol, Nothing}, Vector{Entity}}()
    for node in vcat(species_nodes, reaction_nodes)
        push!(get!(nodes_by_parent, parent_dict[node.name], Entity[]), node)
    end
    links_by_parent = Dict{Union{Symbol, Nothing}, Vector{Link}}()
    for link in rs_network.links
        from_p = parent_dict[link.from]
        to_p = parent_dict[link.to]
        from_p == to_p && !isnothing(from_p) && push!(get!(links_by_parent, from_p, Link[]), link)
    end

    genes = [Entity(kind=:gene, name=k, nodes=nodes_by_parent[k], links=links_by_parent[k])
             for k in keys(nodes_by_parent) if !isnothing(k)]

    (genes, get(nodes_by_parent, nothing, Entity[]), get(links_by_parent, nothing, Link[]))
end

function entity(definition::V1.Definition, f!::Wrapped; include_reactions::Bool=true)
    # extract regulatory links
    reg_links = let
        # ? this also feels equally awkward
        desc = Models.describe(definition)
        components = Dict(typeof(d) => d for d in desc.descriptions)
        [Link(; l...) for l in components[Models.Network].links]
    end

    if include_reactions
        # extract reaction system then partition species and reaction nodes by genes
        # ? is there a better way to do this? this feels kind of awkward
        # also notice here that currently some links will seem to be orphaned unless you flatten the network
        rs = f!.model.definition
        rs_network = entity(rs)
        gene_nodes, aux_nodes, aux_links = _genes_from_reaction_network(rs_network)
        nodes = vcat(gene_nodes, aux_nodes)
        links = vcat(reg_links, aux_links)
    else
        # genes only: no reactions or species nodes
        genes_from_v1 = [Entity(kind=:gene, name=g.name) for g in definition.cascade.genes]
        nodes = genes_from_v1
        links = reg_links
    end

    Entity(
        kind=:v1_model,
        name=:v1_model,
        properties=Dict(:polymerases => definition.polymerases, :ribosomes => definition.ribosomes, :proteasomes => definition.proteasomes),
        nodes=nodes,
        links=links
    )
end

function _collect_core_symbols(t::Differentiation.Transient, symbols::Set{Symbol})
    _collect_core_symbols(t.differentiator, symbols)
    _collect_core_symbols(t.timer, symbols)
    _collect_core_symbols(t.next, symbols)
    _collect_core_symbols(t.alternative, symbols)
end

function _collect_core_symbols(s::Symbol, symbols::Set{Symbol})
    push!(symbols, s)
end

function _collect_core_symbols(g::V1.Gene, symbols::Set{Symbol})
    push!(symbols, g.name)
end

function entity(definition::Differentiation.Definition, f!::Wrapped; kw...)
    v1_entity = entity(f!.model; kw...)

    core_symbols = Set{Symbol}()
    _collect_core_symbols(definition.differentiation, core_symbols)

    core_nodes = [n for n in v1_entity.nodes if n.name in core_symbols]
    core_links = [l for l in v1_entity.links if l.from in core_symbols && l.to in core_symbols]

    diff_core = Entity(
        kind=:differentiation_core,
        name=:differentiation_core,
        nodes=core_nodes,
        links=core_links
    )

    peripheral_nodes = [n for n in v1_entity.nodes if n.name ∉ core_symbols]
    peripheral_links = [l for l in v1_entity.links if !(l.from in core_symbols && l.to in core_symbols)]

    Entity(
        kind=:differentiation_model,
        name=:differentiation_model,
        properties=v1_entity.properties,
        nodes=vcat([diff_core], peripheral_nodes),
        links=peripheral_links
    )
end

entity(f!::Primitive; kw...) = entity(f!.f!; kw...)

entity(f!::Wrapped; kw...) = entity(f!.definition, f!; kw...)

# TODO include more info here?
entity(f!::Instant; kw...) = Entity(kind=:instant, name=:instant)

# simply descend if custom entity not implemented for the definition
# ? maybe we should create nested entities here to tag with information from higher level models?
entity(definition, f!::Wrapped; kw...) = entity(f!.model; kw...)

# flattened hierarchy for downstream use
@kwdef struct Node
    kind::Symbol
    name::Symbol
    parent::Union{Symbol, Nothing} = nothing
    properties::Dict{Symbol, Any} = Dict{Symbol, Any}()
end

Node(entity::Entity, parent::Union{Symbol, Nothing}=nothing) =
    Node(kind=entity.kind, name=entity.name, parent=parent, properties=entity.properties)

function flatten(entity::Entity, parent::Union{Symbol, Nothing}=nothing)::Tuple{Vector{Node}, Vector{Link}}
    nodes = Node[Node(entity, parent)]
    links = copy(entity.links)

    for child in entity.nodes
        child_nodes, child_links = flatten(child, entity.name)
        append!(nodes, child_nodes)
        append!(links, child_links)
    end

    (nodes, links)
end


end
