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
using ..Models: Wrapped, Instant


# TODO: move each method to the model module it belongs to

using GeneRegulatorySystems.Models.SciML: normalize_name

export Link, Entity, entity

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
    SpeciesId(s::SymbolicUtils.BasicSymbolic) = SpeciesId(normalize_name(strip_time(Symbol(s))))
end

function species_components(name::Symbol)
    parts = split(String(name), '.')
    if length(parts) == 1
        return (parent=nothing, species_type=parts[1])
    else
        return (parent=parts[1], species_type=parts[2])
    end
end

parent(name::Symbol) = species_components(name).parent

entity(species::SpeciesId) = let comps = species_components(species.name)
    Entity(
        kind=:species,
        name=species.name,
        properties=Dict(:parent => comps.parent, :species_type => comps.species_type)
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


entity(f!::Primitive) = entity(f!.f!)

entity(f!::Wrapped) = entity(f!.definition, f!)

# simply descend if custom entity not implemented for the definition
entity(definition, f!::Wrapped) = entity(f!.model)

function entity(definition::V1.Definition, f!::Wrapped)
    # extract reaction system
    # ? is there a better way to do this? this feels kind of awkward
    rs = f!.model.definition

    rs_network = entity(rs)

    # partition species by genes
    species_nodes = [n for n in rs_network.nodes if n.kind == :species]
    reaction_nodes = [n for n in rs_network.nodes if n.kind == :reaction]

    nodes_dict = Dict{Union{Symbol, Nothing}, Vector{Entity}}
    links_dict = Dict{Union{Symbol, Nothing}, Vector{Link}}
    for s in species_nodes
        p = get(s.properties, :parent, nothing)
        push!(get!(nodes_dict, p, Entity[]), s)
    end
    # add reaction nodes to a gene if they are fully immersed inside the gene group
    # i.e. all their substrates and products are gene products.
    for r in reaction_nodes
        s = r.from
        p = r.to
        if (parent(p) == parent(s))
            r.properties[:parent] = parent(p)
            push!(nodes_dict[parent(p)], r)
        else
            r.properties[:parent] = nothing
            push!(nodes_dict[nothing], r)
    end
    lookup = node_lookup(rs_network)
    for l in rs_network.links
        if (lookup[l.from].properties[:parent] == lookup[l.to].properties[:parent])
            push!(links_dict[lookup[l.from].properties[:parent]], l)
        else
            push!(links_dict[nothing], l)
    end
    gene_nodes = [Entity(kind=:gene, name=key, nodes=nodes_dict[key], links_dict[key]) for key in keys(nodes_dict)]


    # extract regulatory links
    reg_links = let
        # ? this also feels equally awkward
        desc = Models.describe(definition)
        components = Dict(typeof(d) => d for d in desc.descriptions)
        [Link(; l...) for l in components[Models.Network].links]
    end





    Entity(
        kind=:v1_model,
        name=:v1_model,
        properties=Dict(:polymerases => definition.polymerases, :ribosomes => definition.ribosomes, :proteasomes => definition.proteasomes),
        nodes=vcat(gene_nodes, aux_nodes),
        links=vcat(reg_links, aux_links)
    )

end

function entity(definition::Differentiation.Definition, f!::Wrapped)
    v1_entity = entity(f!.model)

    # here we do a bit of rejigging around
    # we make it so that core differentiation nodes are grouped together
end

function flatten(entity::Entity)
    # flat representation of entity with :parent property set explicitly.
end



end
