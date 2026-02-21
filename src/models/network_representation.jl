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
"""
    Link

Directed edge in the network graph.

- `scope`: `:all` (visible at both zoom levels), `:gene` (zoomed-out only),
  `:species` (zoomed-in only). The frontend resolves endpoints to gene parents
  when zoomed out for `:all`-scoped edges.
"""
@kwdef struct Link
    kind::Symbol
    from::Symbol
    to::Symbol
    properties::Dict{Symbol, Any} = Dict{Symbol, Any}()
    scope::Symbol = :all
end
#kinds: substrate, product, activation, repression, proteolysis, produces, next, alternative
#scopes: all, gene, species

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

    for rxn in Catalyst.reactions(rs)
        _is_regulation_reaction(rxn) && continue

        # Generate deterministic reaction ID from reactants and products
        rxn_name = _reaction_id(rxn)
        push!(nodes, Entity(kind=:reaction, name=rxn_name, properties=Dict(:rate => Symbol(rxn.rate))))

        append!(links,
            [Link(kind=:substrate, from=SpeciesId(s).name, to=rxn_name, properties=Dict(:stoichiometry => rxn.substoich[i]))
             for (i,s) in enumerate(rxn.substrates)]
        )
        append!(links,
            [Link(kind=:product, from=rxn_name, to=SpeciesId(p).name, properties=Dict(:stoichiometry => rxn.prodstoich[i]))
             for (i,p) in enumerate(rxn.products)]
        )
    end

    Entity(kind=:reaction_system,
           name=:reaction_system,
           nodes=nodes,
           links=links)
end

"""
    _is_regulation_reaction(rxn) -> Bool

Check whether a Catalyst Reaction is an activation/deactivation regulation
reaction that should be excluded from the network graph (because the
corresponding regulatory edges already represent this information).

Detection: a reaction involves `*.active` or `*.inactive` species, but NOT
`*.elongations`.  This filters the activation/deactivation reactions generated
by `regulation()` while keeping the trigger reaction (`active + polymerases ->
active + elongations`).
"""
function _is_regulation_reaction(rxn::Reaction)::Bool
    species_names = String[]
    for s in rxn.substrates
        push!(species_names, String(SpeciesId(s).name))
    end
    for p in rxn.products
        push!(species_names, String(SpeciesId(p).name))
    end

    has_active = any(n -> endswith(n, ".active") || endswith(n, ".inactive"), species_names)
    has_elongations = any(n -> endswith(n, ".elongations"), species_names)

    return has_active && !has_elongations
end

"""
Generate a deterministic reaction ID from substrates and products.
Format: [stoich]species;[stoich]species->[stoich]species;[stoich]species
Example: [2]1.mRNA;[1]1.protein->[1]1.mRNA;[2]1.protein
"""
function _reaction_id(rxn::Reaction)::Symbol
    substrates = [
        string("[", rxn.substoich[i], "]", SpeciesId(s).name)
        for (i, s) in enumerate(rxn.substrates)
    ]
    products = [
        string("[", rxn.prodstoich[i], "]", SpeciesId(p).name)
        for (i, p) in enumerate(rxn.products)
    ]
    return Symbol(join(substrates, ";") * "->" * join(products, ";"))
end

"""
    _genes_from_reaction_network(rs_network) -> (genes, aux_nodes, aux_links, summary_links)

Partition species and reaction nodes from a reaction system into gene groups.

1. Species with a dotted name (e.g. `A.proteins`) get parent from the prefix.
2. Orphan species whose producing reactions draw ALL substrates from ONE gene
   are adopted by that gene (e.g. homodimer `AA` from `A+A`).
3. Reactions connecting species of a single gene are placed inside that gene.
4. Cross-gene orphan products get `produces` summary links (scope=:gene)
   from each contributing gene, for the zoomed-out view.
5. Intra-gene substrate/product links are tagged scope=:species.
"""
function _genes_from_reaction_network(rs_network::Entity)::Tuple{Vector{Entity}, Vector{Entity}, Vector{Link}, Vector{Link}}

    species_nodes = [n for n in rs_network.nodes if n.kind == :species]
    reaction_nodes = [n for n in rs_network.nodes if n.kind == :reaction]

    # Initial parent assignment from dotted names (e.g. A.proteins -> parent A)
    parent_dict = Dict(s.name => parent(s.name) for s in species_nodes)

    # Index links by endpoint for fast lookup
    links_by_to = Dict{Symbol, Vector{Link}}()
    links_by_from = Dict{Symbol, Vector{Link}}()
    for link in rs_network.links
        push!(get!(links_by_to, link.to, Link[]), link)
        push!(get!(links_by_from, link.from, Link[]), link)
    end

    # Second pass: adopt orphan species produced by single-gene reactions.
    # If ALL substrates of a reaction producing an orphan species belong to
    # the same gene, assign the orphan species to that gene.
    for s in species_nodes
        !isnothing(parent_dict[s.name]) && continue  # already parented

        # Find reactions that produce this species
        producing_reactions = [link.from for link in get(links_by_to, s.name, Link[])
                               if link.kind == :product]
        isempty(producing_reactions) && continue

        # Collect genes of ALL substrates across all producing reactions
        substrate_genes = Set{Symbol}()
        for rxn_name in producing_reactions
            for sub_link in get(links_by_to, rxn_name, Link[])
                sub_link.kind == :substrate || continue
                sub_parent = get(parent_dict, sub_link.from, nothing)
                !isnothing(sub_parent) && push!(substrate_genes, sub_parent)
            end
        end

        # Adopt only if all substrates come from a single gene
        if length(substrate_genes) == 1
            parent_dict[s.name] = first(substrate_genes)
        end
    end

    # Assign reaction parents: single-gene if all connected species share one gene
    for r in reaction_nodes
        connected_parents = Set{Symbol}()
        for link in get(links_by_to, r.name, Link[])
            p = get(parent_dict, link.from, nothing)
            !isnothing(p) && push!(connected_parents, p)
        end
        for link in get(links_by_from, r.name, Link[])
            p = get(parent_dict, link.to, nothing)
            !isnothing(p) && push!(connected_parents, p)
        end
        parent_dict[r.name] = length(connected_parents) == 1 ? first(connected_parents) : nothing
    end

    # Group nodes by parent
    nodes_by_parent = Dict{Union{Symbol, Nothing}, Vector{Entity}}()
    for node in vcat(species_nodes, reaction_nodes)
        push!(get!(nodes_by_parent, parent_dict[node.name], Entity[]), node)
    end

    # Group intra-gene links (scope=:species) and collect cross-gene links
    links_by_parent = Dict{Union{Symbol, Nothing}, Vector{Link}}()
    for link in rs_network.links
        from_p = get(parent_dict, link.from, nothing)
        to_p = get(parent_dict, link.to, nothing)
        if from_p == to_p && !isnothing(from_p)
            tagged = Link(; kind=link.kind, from=link.from, to=link.to,
                           properties=link.properties, scope=:species)
            push!(get!(links_by_parent, from_p, Link[]), tagged)
        end
    end

    # Build gene entities
    genes = [Entity(kind=:gene, name=k,
                    nodes=get(nodes_by_parent, k, Entity[]),
                    links=get(links_by_parent, k, Link[]))
             for k in keys(nodes_by_parent) if !isnothing(k)]

    # Tag cross-gene substrate/product links as scope=:species
    aux_links = Link[]
    for link in rs_network.links
        from_p = get(parent_dict, link.from, nothing)
        to_p = get(parent_dict, link.to, nothing)
        (from_p == to_p && !isnothing(from_p)) && continue  # already in gene
        push!(aux_links, Link(; kind=link.kind, from=link.from, to=link.to,
                               properties=link.properties, scope=:species))
    end

    # Generate summary `produces` links (scope=:gene) for orphan species.
    # These show gene-to-orphan connections when zoomed out.
    summary_links = Link[]
    gene_names = Set(k for k in keys(nodes_by_parent) if !isnothing(k))
    for s in species_nodes
        !isnothing(parent_dict[s.name]) && continue  # not orphan

        # Find contributing genes via substrate parents of producing reactions
        contributing_genes = Set{Symbol}()
        for prod_link in get(links_by_to, s.name, Link[])
            prod_link.kind == :product || continue
            for sub_link in get(links_by_to, prod_link.from, Link[])
                sub_link.kind == :substrate || continue
                sub_parent = get(parent_dict, sub_link.from, nothing)
                !isnothing(sub_parent) && push!(contributing_genes, sub_parent)
            end
        end

        for gene in contributing_genes
            push!(summary_links, Link(
                kind=:produces, from=gene, to=s.name,
                properties=Dict{Symbol, Any}(), scope=:gene,
            ))
        end
    end

    (genes, get(nodes_by_parent, nothing, Entity[]), aux_links, summary_links)
end

"""
    _resolve_reg_endpoint(name, gene_names, suffix) -> Symbol

Resolve a regulatory link endpoint to species level.
If `name` is a gene, append `.suffix` (e.g. `:A` -> `Symbol("A.proteins")`).
Otherwise keep as-is (e.g. `:AA` stays `:AA`).
"""
function _resolve_reg_endpoint(name::Symbol, gene_names::Set{Symbol}, suffix::String)::Symbol
    name in gene_names ? Symbol("$(name).$(suffix)") : name
end

function entity(definition::V1.Definition, f!::Wrapped; include_reactions::Bool=true)
    gene_names = Set{Symbol}(g.name for g in definition.genes)

    desc = Models.describe(definition)
    components = Dict(typeof(d) => d for d in desc.descriptions)
    raw_links = components[Models.Network].links

    if include_reactions
        # Species-level resolution for regulatory links
        reg_links = map(raw_links) do l
            from_resolved = _resolve_reg_endpoint(l.from, gene_names, "proteins")
            to_suffix = l.kind == :proteolysis ? "proteins" : "active"
            to_resolved = _resolve_reg_endpoint(l.to, gene_names, to_suffix)
            Link(; kind=l.kind, from=from_resolved, to=to_resolved,
                  properties=l.properties, scope=:all)
        end

        rs = f!.model.definition
        rs_network = entity(rs)
        gene_nodes, aux_nodes, aux_links, summary_links = _genes_from_reaction_network(rs_network)
        nodes = vcat(gene_nodes, aux_nodes)
        links = vcat(reg_links, aux_links, summary_links)
    else
        # Kronecker/random-diff: no species, keep gene-level regulatory links
        reg_links = [Link(; l..., scope=:all) for l in raw_links]
        nodes = [Entity(kind=:gene, name=g.name) for g in definition.genes]
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

# Kronecker networks: always skip species/reaction detail (too large)
function entity(definition::KroneckerNetworks.Definition, f!::Wrapped; include_reactions=true, kw...)
    v1_entity = entity(f!.model; include_reactions=false, kw...)
    Entity(
        kind=:kronecker_network,
        name=:kronecker_network,
        properties=v1_entity.properties,
        nodes=v1_entity.nodes,
        links=v1_entity.links
    )
end

# Random differentiation: always skip species/reaction detail (too large)
function entity(definition::RandomDifferentiation.Definition, f!::Wrapped; include_reactions=true, kw...)
    v1_entity = entity(f!.model; include_reactions=false, kw...)
    Entity(
        kind=:random_differentiation,
        name=:random_differentiation,
        properties=v1_entity.properties,
        nodes=v1_entity.nodes,
        links=v1_entity.links
    )
end

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
