"""
    ScheduleVisualization

Converts GRS.jl Schedule objects into frontend-compatible visualisation schemas.
Handles schedule reification, validation, structure tree generation, and
on-demand network extraction.
"""
module ScheduleVisualization

using GeneRegulatorySystems
using GeneRegulatorySystems.Models
using GeneRegulatorySystems.Models: Wrapped, Instant, Label, Descriptions, Differentiation, KroneckerNetworks, RandomDifferentiation
using GeneRegulatorySystems.Models.V1
using GeneRegulatorySystems.Models.Plumbing
using GeneRegulatorySystems.Models.Scheduling
using GeneRegulatorySystems.Models.Scheduling: Primitive, Schedule as GRSSchedule
using GeneRegulatorySystems.Models.NetworkRepresentation
using GeneRegulatorySystems.Specifications
using GeneRegulatorySystems.Specifications: Scope, List, Each, Load, Template, Slice, Sequence
using JSON
using Colors

# ============================================================================
# Exports
# ============================================================================

export Network, UnionNetwork, ModelExclusions, TimelineSegment, ScheduleData, StructureNode
export ReifiedSchedule, ValidationMessage
export reify_schedule, extract_network_for_model_path, extract_union_network, is_valid, get_error_messages

# ============================================================================
# Schema Types
# ============================================================================

@kwdef struct Network
    nodes::Vector{NetworkRepresentation.Node}
    links::Vector{NetworkRepresentation.Link}
end

"""
    ModelExclusions

Nodes and links absent from a specific model (relative to the union).
"""
@kwdef struct ModelExclusions
    nodes::Vector{String}
    links::Vector{String}
end

"""
    UnionNetwork

Union of all model networks. `model_exclusions` maps each model_path to the
nodes/links that are NOT present in that model.
"""
@kwdef struct UnionNetwork
    nodes::Vector{NetworkRepresentation.Node}
    links::Vector{NetworkRepresentation.Link}
    model_exclusions::Dict{String, ModelExclusions}
end

"""
    TimelineSegment

Single execution segment from a dryrun pass.

- `id`: auto-increment unique identifier
- `execution_path`: dryrun `path` kwarg (not unique for repeating scopes)
- `model_path`: `primitive!.path` (spec location, used for network loading)
- `json_path`: JSONPath segments for locating the model definition in the source JSON
- `from`/`to`: time range (from == to for instant models)
- `label`: human-readable model label
"""
@kwdef struct TimelineSegment
    id::Int
    execution_path::String
    model_path::String
    json_path::Vector{Any}
    from::Float64
    to::Float64
    label::String
end

"""
    StructureNode

Recursive tree mirroring the schedule specification structure.
Used by the frontend to compute rectangle layout for timeline/promoter charts.

- `type`: `:scope`, `:sequence`, `:branch`, `:leaf`
- `execution_path`: the execution path prefix for this node
- `label`: human-readable label (from spec)
- `children`: child nodes (empty for leaves)
"""
@kwdef struct StructureNode
    type::Symbol
    execution_path::String = ""
    label::String = ""
    children::Vector{StructureNode} = StructureNode[]
end

"""
    ScheduleData

Complete visualisation schema. No network included -- networks are loaded on demand.

- `segments`: all timeline segments (with contiguous same-path merging)
- `structure`: recursive tree from spec for rectangle layout
- `genes`: sorted gene names from all models
- `gene_colours`: gene name to hex colour string
"""
@kwdef struct ScheduleData
    segments::Vector{TimelineSegment}
    structure::StructureNode
    genes::Vector{String} = String[]
    gene_colours::Dict{String, String} = Dict{String, String}()
end

# ============================================================================
# API Types
# ============================================================================

@kwdef struct ValidationMessage
    type::String
    content::String
end

"""
    ReifiedSchedule

Loaded schedule with metadata and visualisation data.
"""
@kwdef struct ReifiedSchedule
    name::String
    source::String
    spec::String
    data::Union{ScheduleData, Nothing} = nothing
    validationMessages::Vector{ValidationMessage} = ValidationMessage[]
end

# ============================================================================
# Public API
# ============================================================================

"""
    reify_schedule(spec_string; name, source) -> ReifiedSchedule

Parse, validate, and build visualisation data for a schedule spec string.
"""
function reify_schedule(spec_string::String; name::String="", source::String="snapshot")::ReifiedSchedule
    start_time = time()
    validation_messages = ValidationMessage[]
    visualisation = nothing

    try
        spec = JSON.parse(spec_string, dicttype=Dict{Symbol, Any})

        validation_msgs = _validate_spec(spec)
        append!(validation_messages, validation_msgs)

        has_errors = any(m -> m.type == "error", validation_messages)
        if !has_errors
            @info "Generating schedule visualisation" name source
            vis_start = time()

            bindings = _spec_bindings(spec)
            specification = Specifications.Specification(spec; bound = Set(keys(bindings)))
            grs_schedule = GRSSchedule(; specification, bindings)

            segments, genes, gene_colours = _collect_segments(grs_schedule)
            merged = _merge_contiguous_segments(segments)
            structure = _build_structure_tree(grs_schedule)

            @info "Schedule visualisation generated" name segments=length(merged) genes=length(genes) elapsed=(time() - vis_start)

            visualisation = ScheduleData(;
                segments = merged,
                structure,
                genes,
                gene_colours,
            )
        end
    catch e
        push!(validation_messages, ValidationMessage(
            type = "error",
            content = "Failed to process schedule: $(string(e))"
        ))
        @error "Schedule processing failed" exception=e
    end

    @info "Schedule load completed" name source valid=!any(m -> m.type == "error", validation_messages) elapsed=(time() - start_time)

    return ReifiedSchedule(; name, source, spec = spec_string, data = visualisation, validationMessages = validation_messages)
end

"""
    extract_network_for_model_path(grs_schedule, model_path) -> Network

Extract the network for a specific model path using `Scheduling.reify`.
"""
function extract_network_for_model_path(grs_schedule::GRSSchedule, model_path::String; include_reactions::Bool=true)::Network
    @debug "Extracting network for model_path" model_path include_reactions
    primitive = Scheduling.reify(grs_schedule, model_path)
    entity = NetworkRepresentation.entity(primitive; include_reactions)
    nodes, links = NetworkRepresentation.flatten(entity)
    return Network(; nodes, links)
end

"""
    extract_network_for_model_path(spec_string, model_path) -> Network

Convenience: parse spec string and extract network.
"""
function extract_network_for_model_path(spec_string::String, model_path::String)::Network
    spec = JSON.parse(spec_string, dicttype=Dict{Symbol, Any})
    bindings = _spec_bindings(spec)
    specification = Specifications.Specification(spec; bound = Set(keys(bindings)))
    grs_schedule = GRSSchedule(; specification, bindings)
    return extract_network_for_model_path(grs_schedule, model_path)
end

"""
    extract_union_network(spec_string, segments) -> UnionNetwork

Build the union network across all model paths in the schedule segments.
Each model's exclusions (nodes/links absent from that model) are recorded.
"""
function extract_union_network(spec_string::String, segments::Vector{TimelineSegment}; include_reactions::Bool=true)::UnionNetwork
    spec = JSON.parse(spec_string, dicttype=Dict{Symbol, Any})
    bindings = _spec_bindings(spec)
    specification = Specifications.Specification(spec; bound = Set(keys(bindings)))
    grs_schedule = GRSSchedule(; specification, bindings)

    # Collect per-model networks
    model_paths = _unique_model_paths(segments)
    per_model = Dict{String, Network}()
    for mp in model_paths
        try
            per_model[mp] = extract_network_for_model_path(grs_schedule, mp; include_reactions)
        catch e
            @warn "Could not extract network for model_path" model_path=mp exception=e
        end
    end

    # Build union
    all_nodes = Dict{String, NetworkRepresentation.Node}()
    all_links = Dict{String, NetworkRepresentation.Link}()
    for (_, net) in per_model
        for n in net.nodes
            all_nodes[string(n.name)] = n
        end
        for l in net.links
            all_links[_link_id(l)] = l
        end
    end

    union_node_names = Set(keys(all_nodes))
    union_link_ids = Set(keys(all_links))

    # Build exclusions per model
    model_exclusions = Dict{String, ModelExclusions}()
    for (mp, net) in per_model
        model_node_names = Set(string(n.name) for n in net.nodes)
        model_link_ids = Set(_link_id(l) for l in net.links)
        model_exclusions[mp] = ModelExclusions(
            nodes = collect(setdiff(union_node_names, model_node_names)),
            links = collect(setdiff(union_link_ids, model_link_ids)),
        )
    end

    @info "Union network built" nodes=length(all_nodes) links=length(all_links) models=length(per_model)
    return UnionNetwork(
        nodes = collect(values(all_nodes)),
        links = collect(values(all_links)),
        model_exclusions = model_exclusions,
    )
end

# ============================================================================
# Internal: model_path → JSONPath conversion
# ============================================================================

"""
    model_path_to_json_path(model_path) -> Vector{Any}

Convert an internal model_path string (e.g. `"+-1.do"`) to a JSONPath segment
array suitable for use with `jsonc-parser`'s `findNodeAtLocation`.

Encoding rules:
- `+` or `/`  → descend into the `"step"` key (scope entry)
- `-`          → list separator, no JSON descent
- digits       → 0-based array index (Julia paths are 1-based)
- `.name`      → descend into binding key `name`
"""
function model_path_to_json_path(model_path::String)::Vector{Any}
    result = Any[]
    chars = collect(model_path)
    n = length(chars)
    i = 1
    while i <= n
        c = chars[i]
        if c == '+' || c == '/'
            push!(result, "step")
            i += 1
        elseif c == '-'
            i += 1  # list separator — no JSON key descent
        elseif c == '.'
            j = i + 1
            while j <= n && chars[j] ∉ ('+', '/', '-', '.')
                j += 1
            end
            push!(result, String(chars[i+1:j-1]))
            i = j
        elseif isdigit(c)
            j = i
            while j <= n && isdigit(chars[j])
                j += 1
            end
            push!(result, parse(Int, String(chars[i:j-1])) - 1)  # 0-based
            i = j
        else
            i += 1
        end
    end
    return result
end

function _unique_model_paths(segments::Vector{TimelineSegment})::Vector{String}
    seen = Set{String}()
    paths = String[]
    for seg in segments
        seg.from == seg.to && continue
        if seg.model_path ∉ seen
            push!(seen, seg.model_path)
            push!(paths, seg.model_path)
        end
    end
    return paths
end

function _link_id(l::NetworkRepresentation.Link)::String
    return "$(l.from)-$(l.kind)-$(l.to)"
end

is_valid(reified::ReifiedSchedule)::Bool = !any(msg -> msg.type == "error", reified.validationMessages)

function get_error_messages(reified::ReifiedSchedule)::String
    error_msgs = filter(msg -> msg.type == "error", reified.validationMessages)
    return join([msg.content for msg in error_msgs], "; ")
end

# ============================================================================
# Internal: Label Extraction
# ============================================================================

_label(wrapped::Models.Wrapped) = _label(Models.describe(wrapped.definition))
_label(label::Models.Label) = label.label
_label(::Models.EmptyDescription) = ""
_label(x) = _type_label(x)

function _label(model::Plumbing.Adjust)
    op = try nameof(model.adjust) catch; :adjust end
    entries = join(
        ("  $(k): $(v)" for (k, v) in sort(collect(model.adjustment), by = first ∘ string)),
        "\n",
    )
    body = "Adjust ($(op))"
    isempty(entries) ? body : "$(body)\n$(entries)"
end

function _label(model::Plumbing.Seed)
    "Seed\n  $(model.seed)"
end

function _label(desc::Descriptions)
    i = findfirst(d -> d isa Label, desc.descriptions)
    i !== nothing ? _label(desc.descriptions[i]) : ""
end

"""Human-readable label derived from a model's type name (e.g. ResampleEachBinomial -> "resample each binomial")."""
function _type_label(x)::String
    name = string(nameof(typeof(x)))
    # CamelCase -> space-separated lowercase
    words = replace(name, r"([a-z])([A-Z])" => s"\1 \2")
    return lowercase(words)
end

"""Extract seed from a parsed spec (Dict or Vector)."""
_spec_seed(spec::AbstractDict{Symbol}) = get(spec, :seed, "default")
_spec_seed(::AbstractVector) = "default"

"""Build standard bindings from a parsed spec."""
function _spec_bindings(spec)
    Dict(
        :seed => _spec_seed(spec),
        :into => "",
        :channel => "",
        :defaults => Models.load_defaults(),
    )
end

# ============================================================================
# Internal: Segment Collection
# ============================================================================

"""
Collect all raw segments, gene names, and gene colours from a single dryrun pass.
Gene colours are generated per-model using dispatch (`_gene_colours`).
Returns `(segments, gene_names, gene_colours)` — deduplicated per model_path.
"""
function _collect_segments(grs_schedule)::Tuple{Vector{TimelineSegment}, Vector{String}, Dict{String, String}}
    segments = TimelineSegment[]
    next_id = Ref(1)
    genes = Set{String}()
    gene_colours = Dict{String, String}()
    seen_model_paths = Set{String}()

    # TODO: use a custom approach to collect segments
    # the dryrun of the schedule still has to construct all the models
    # if I want to load a large kronecker graph, i dont care about the reaction network
    # so I can skip building the model if I only care about the gene-level network and segments

    function dryrun_collector(primitive!, x, Δt; path, _...)
        label = _label(primitive!.f!.model)
        model_path = primitive!.path
        push!(segments, TimelineSegment(
            id = next_id[],
            execution_path = path,
            model_path = model_path,
            json_path = model_path_to_json_path(model_path),
            from = x.t,
            to = x.t + (isfinite(Δt) ? Δt : 0.0),
            label = label,
        ))
        next_id[] += 1

        if model_path ∉ seen_model_paths && isfinite(Δt) && Δt > 0.0
            push!(seen_model_paths, model_path)
            for name in _gene_names(primitive!)
                push!(genes, string(name))
            end
            merge!(gene_colours, _gene_colours(primitive!))
        end
    end

    grs_schedule(Models.FlatState(); dryrun = dryrun_collector)
    return (segments, sort(collect(genes)), gene_colours)
end

"""
Merge contiguous segments with the same execution_path, label, and model_path.
Non-contiguous segments with the same path (e.g., entrained model) stay separate.
IDs are reassigned after merging.
"""
function _merge_contiguous_segments(segments::Vector{TimelineSegment})::Vector{TimelineSegment}
    isempty(segments) && return TimelineSegment[]

    merged = TimelineSegment[]
    current = segments[1]

    for i in 2:length(segments)
        seg = segments[i]
        if seg.execution_path == current.execution_path &&
           seg.label == current.label &&
           seg.model_path == current.model_path &&
           seg.from == current.to
            current = TimelineSegment(
                id = current.id,
                execution_path = current.execution_path,
                model_path = current.model_path,
                json_path = current.json_path,
                from = current.from,
                to = seg.to,
                label = current.label,
            )
        else
            push!(merged, current)
            current = seg
        end
    end
    push!(merged, current)

    return [TimelineSegment(
        id = i,
        execution_path = seg.execution_path,
        model_path = seg.model_path,
        json_path = seg.json_path,
        from = seg.from,
        to = seg.to,
        label = seg.label
    ) for (i, seg) in enumerate(merged)]
end

# Internal: Structure Tree
# ============================================================================

"""
Walk the Schedule specification tree to produce a StructureNode hierarchy.
"""
function _build_structure_tree(grs_schedule::GRSSchedule)::StructureNode
    return _structure_node(grs_schedule.specification, grs_schedule.bindings, grs_schedule.path, grs_schedule.branch)
end

function _structure_node(spec::Scope, bindings::Dict{Symbol, Any}, path::String, branch::Bool)::StructureNode
    child_path = "$path$(spec.branch ? '/' : '+')"
    merged_bindings = _safe_evaluate_bindings(spec, bindings, path)
    child = _structure_node_from_step(spec.step, merged_bindings, child_path, spec.branch)

    if haskey(merged_bindings, :to)
        return StructureNode(type = :scope, execution_path = child_path, label = "repeat", children = [child])
    end

    return StructureNode(type = :scope, execution_path = child_path, children = [child])
end

function _structure_node(spec::List, bindings::Dict{Symbol, Any}, path::String, branch::Bool)::StructureNode
    child_prefix = branch ? path : "$path-"
    children = StructureNode[]

    for (i, item_spec) in enumerate(spec.items)
        item_bindings = Scheduling.descended(bindings, i)
        child = _structure_node_from_step(item_spec, item_bindings, "$child_prefix$i", false)
        push!(children, child)
    end

    node_type = (branch || any(_subtree_has_branch, children)) ? :branch : :sequence
    return StructureNode(type = node_type, execution_path = path, children = children)
end

function _structure_node(spec::Each, bindings::Dict{Symbol, Any}, path::String, branch::Bool)::StructureNode
    child_prefix = branch ? path : "$path-"

    items = try
        Scheduling.evaluate(spec.items; bindings, path)
    catch
        []
    end

    children = StructureNode[]
    for (i, item) in enumerate(items)
        item_bindings = Scheduling.descended(bindings, i)
        if spec.as != Symbol("")
            item_bindings = merge(item_bindings, Dict{Symbol, Any}(spec.as => item))
        end
        child = _structure_node_from_step(spec.step, item_bindings, "$child_prefix$i", false)
        push!(children, child)
    end

    node_type = (branch || any(_subtree_has_branch, children)) ? :branch : :sequence
    return StructureNode(type = node_type, execution_path = path, children = children)
end

"""True if this node or any descendant has type :branch."""
function _subtree_has_branch(node::StructureNode)::Bool
    node.type == :branch && return true
    any(_subtree_has_branch, node.children)
end

function _structure_node(spec::Template, bindings::Dict{Symbol, Any}, path::String, branch::Bool)::StructureNode
    expanded = try
        Scheduling.evaluate(spec; bindings, path)
    catch
        nothing
    end

    if expanded isa Specifications.Specification
        return _structure_node(expanded, bindings, path, branch)
    end

    return StructureNode(type = :leaf, execution_path = path, label = _safe_label(expanded))
end

function _structure_node(spec::Slice, bindings::Dict{Symbol, Any}, path::String, branch::Bool)::StructureNode
    return StructureNode(type = :leaf, execution_path = path, label = "slice")
end

function _structure_node(spec::Load, bindings::Dict{Symbol, Any}, path::String, branch::Bool)::StructureNode
    return StructureNode(type = :leaf, execution_path = path, label = "load: $(spec.path)")
end

function _structure_node(spec, bindings::Dict{Symbol, Any}, path::String, branch::Bool)::StructureNode
    return StructureNode(type = :leaf, execution_path = path)
end

function _structure_node_from_step(step, bindings::Dict{Symbol, Any}, path::String, branch::Bool)::StructureNode
    if step isa Specifications.Specification
        return _structure_node(step, bindings, path, branch)
    end
    return StructureNode(type = :leaf, execution_path = path, label = _safe_label(step))
end

function _safe_evaluate_bindings(spec::Scope, bindings::Dict{Symbol, Any}, path::String)::Dict{Symbol, Any}
    try
        merged = if spec.barrier
            Dict{Symbol, Any}(
                keep => bindings[keep]
                for keep in (:seed, :into, :channel, :defaults)
                if haskey(bindings, keep)
            )
        else
            copy(bindings)
        end

        for (name, definition) in spec.definitions
            try
                merged[name] = Scheduling.evaluate(definition, path = "$path.$name"; bindings)
                merged[Symbol("^$name")] = Scheduling.Locator(path)
            catch
                @debug "Could not evaluate binding" name path
            end
        end
        return merged
    catch
        return bindings
    end
end

_safe_label(x::Models.Model) = _label(x)
_safe_label(x::Models.Wrapped) = _label(x)
_safe_label(x::Number) = "step=$x"
_safe_label(::Nothing) = ""
_safe_label(x) = string(typeof(x))

# ============================================================================
# Internal: Gene Name Extraction
# ============================================================================

# Lightweight gene name extraction via multiple dispatch.
# Descends through Wrapped layers to find V1.Definition without building networks.
_gene_names(primitive::Primitive) = _gene_names(primitive.f!)
_gene_names(wrapped::Wrapped) = _gene_names(wrapped.definition, wrapped)
_gene_names(::V1.Definition, wrapped::Wrapped) = Symbol[g.name for g in wrapped.definition.genes]
_gene_names(_, wrapped::Wrapped) = _gene_names(wrapped.model)  # descend through Wrapped layers
_gene_names(_) = Symbol[]  # fallback for non-gene models (e.g. resampling)

# ============================================================================
# Internal: Gene Colours
# ============================================================================

_hsl_hex(h::Float64, s::Float64, l::Float64)::String =
    "#$(hex(convert(RGB, HSL(h, s, l))))"

# Generate maximally-distinct pastel colours for a plain list of gene names.
function _generate_gene_colours(gene_names::Vector{String})::Dict{String, String}
    isempty(gene_names) && return Dict{String, String}()
    seed = [colorant"white", colorant"black", colorant"crimson", colorant"green"]
    colors = distinguishable_colors(length(gene_names), seed, dropseed = true)
    # Pastel: low saturation, high value
    colors = [let hsv = HSV(c); HSV(hsv.h, hsv.s * 0.65, min(hsv.v * 1.8, 1.0)) end for c in colors]
    colors = convert.(RGB, colors)
    return Dict(string(gene) => "#$(hex(colors[i]))" for (i, gene) in enumerate(gene_names))
end

# Evenly-spaced gray shades between light and dark for Kronecker/peripheral genes.
function _gray_colours(gene_names::Vector{String})::Dict{String, String}
    isempty(gene_names) && return Dict{String, String}()
    n = length(gene_names)
    return Dict(
        name => _hsl_hex(0.0, 0.0, 0.62 - 0.20 * (i - 1) / max(1, n - 1))
        for (i, name) in enumerate(gene_names)
    )
end

# ── Differentiation tree colouring ──────────────────────────────────────────
# Top-down arc-splitting: the root owns a centre hue and a total arc.
# Each level splits the arc in half and assigns left/right children to the
# two sub-centres.  The parent hue is structurally the midpoint of its
# children — proper paint-mixing by construction, no bottom-up pass needed.
# Saturation and lightness scale up with depth so leaves are vivid and
# ancestors are progressively muddier.

_diff_gene_name(g::V1.Gene)::Symbol = g.name
_diff_gene_name(s::Symbol)::Symbol  = s

# Centre hue (degrees) and initial half-arc for the root differentiator.
# The range [centre-arc … centre+arc] at full depth stays well clear of
# pure red (0°/360°) and pure green (120°).
const _DIFF_HUE_CENTER      = 220.0   # blue
const _DIFF_HUE_INITIAL_ARC = 100.0   # ± from centre at root; doubles down the tree

_diff_saturation(depth::Int)::Float64 = clamp(0.18 + depth * 0.14, 0.18, 0.78)
_diff_lightness(depth::Int)::Float64  = clamp(0.30 + depth * 0.08, 0.30, 0.64)

# Assign colour to a Transient node then recurse into children.
# `centre` is the hue for this node; `half_arc` is half the arc it owns.
function _assign_diff_colours!(
    t::Differentiation.Transient,
    centre::Float64,
    half_arc::Float64,
    depth::Int,
    colours::Dict{String, String},
)
    hue = mod(centre, 360.0)
    s   = _diff_saturation(depth)
    l   = _diff_lightness(depth)
    colours[string(_diff_gene_name(t.differentiator))] = _hsl_hex(hue, s, l)
    # Timer: same hue, lighter and less saturated (name derived per make_timer! convention)
    timer_name = Symbol(string(_diff_gene_name(t.differentiator)) * "_timer")
    colours[string(timer_name)] = _hsl_hex(hue, max(s - 0.12, 0.08), min(l + 0.18, 0.82))
    child_half = half_arc / 2.0
    _assign_diff_child!(t.next,        centre - half_arc / 2.0, child_half, depth + 1, colours)
    _assign_diff_child!(t.alternative, centre + half_arc / 2.0, child_half, depth + 1, colours)
end

# Recurse into a child that is itself a Transient.
function _assign_diff_child!(t::Differentiation.Transient, centre, half_arc, depth, colours)
    _assign_diff_colours!(t, centre, half_arc, depth, colours)
end

# Leaf: just assign the colour at the given hue.
function _assign_diff_child!(g::V1.Gene, centre, _, depth, colours)
    colours[string(g.name)] = _hsl_hex(mod(centre, 360.0), _diff_saturation(depth), _diff_lightness(depth))
end
function _assign_diff_child!(sym::Symbol, centre, _, depth, colours)
    colours[string(sym)] = _hsl_hex(mod(centre, 360.0), _diff_saturation(depth), _diff_lightness(depth))
end

# Generate colours for a fully-instantiated Differentiation.Definition.
# Core differentiators → tree hues; timers → same hue lighter; peripheral → grays.
function _diff_colours(def::Differentiation.Definition)::Dict{String, String}
    colours = Dict{String, String}()
    _assign_diff_colours!(def.differentiation, _DIFF_HUE_CENTER, _DIFF_HUE_INITIAL_ARC, 0, colours)
    peripheral_names = String[string(g.name) for g in def.peripheral.genes]
    merge!(colours, _gray_colours(peripheral_names))
    return colours
end

# ── Per-model dispatch ───────────────────────────────────────────────────────

_gene_colours(primitive::Primitive)             = _gene_colours(primitive.f!)
_gene_colours(wrapped::Wrapped)                 = _gene_colours(wrapped.definition, wrapped)

# Random differentiation: delegate to the instantiated Differentiation.Definition
function _gene_colours(::RandomDifferentiation.Definition, wrapped::Wrapped)
    _diff_colours(wrapped.model.definition)
end

# Plain differentiation: fall through to V1 via generic descent
function _gene_colours(::KroneckerNetworks.Definition, wrapped::Wrapped)
    gene_names = String[string(g.name) for g in wrapped.model.definition.genes]
    _gray_colours(gene_names)
end

# Plain V1: maximally-distinct pastel colours
function _gene_colours(def::V1.Definition, ::Wrapped)
    gene_names = String[string(g.name) for g in def.genes]
    _generate_gene_colours(gene_names)
end

# Descend through unrecognised Wrapped layers
_gene_colours(_, wrapped::Wrapped) = _gene_colours(wrapped.model)
_gene_colours(_)                   = Dict{String, String}()

# ============================================================================
# Internal: Validation
# ============================================================================

function _validate_spec(spec::AbstractDict{Symbol})::Vector{ValidationMessage}
    messages = ValidationMessage[]

    if isempty(spec)
        push!(messages, ValidationMessage(type="error", content="Schedule specification is empty"))
        return messages
    end

    if haskey(spec, :seed)
        if !isa(spec[:seed], String)
            push!(messages, ValidationMessage(type="warning", content="Seed should be a string (got $(typeof(spec[:seed])))"))
        end
    else
        push!(messages, ValidationMessage(type="info", content="No seed specified (will use default)"))
    end

    try
        Models.Model(
            spec,
            bindings = Dict(
                :seed => get(spec, :seed, "default"),
                :into => "",
                :channel => "",
                :defaults => Models.load_defaults(),
            ),
        )
    catch e
        push!(messages, ValidationMessage(type="error", content="Schedule validation failed: $(string(e))"))
    end

    return messages
end

function _validate_spec(spec::AbstractVector)::Vector{ValidationMessage}
    messages = ValidationMessage[]

    if isempty(spec)
        push!(messages, ValidationMessage(type="error", content="Schedule specification is empty"))
        return messages
    end

    push!(messages, ValidationMessage(type="info", content="No seed specified (will use default)"))

    try
        Models.Model(
            spec,
            bindings = Dict(
                :seed => "default",
                :into => "",
                :channel => "",
                :defaults => Models.load_defaults(),
            ),
        )
    catch e
        push!(messages, ValidationMessage(type="error", content="Schedule validation failed: $(string(e))"))
    end

    return messages
end

end # module ScheduleVisualization
