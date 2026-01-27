"""
    ScheduleVisualization

Module for schedule visualization schema generation and validation.

Converts GRS.jl Schedule objects into frontend-compatible visualization schemas
and validates schedule specifications before execution.
"""
module ScheduleVisualization

using GeneRegulatorySystems
using GeneRegulatorySystems.Models
using GeneRegulatorySystems.Models.Scheduling
using GeneRegulatorySystems.Models.V1
using GeneRegulatorySystems.Specifications
using JSON
using Colors

# ============================================================================
# Exports
# ============================================================================

# Schema types (frontend contract)
export Entity, SpeciesEntity, ReactionEntity, GeneEntity, DifferentiatorEntity
export Network, TimelineSegment, ScheduleData, ScheduleVisMetadata

# API types
export ReifiedSchedule, ValidationMessage

# Public API
export reify_schedule, extract_network, is_valid, get_error_messages

# ============================================================================
# Schema Types
# ============================================================================

"""
    ScheduleVisMetadata

Visualization metadata for schedule rendering.

Contains aesthetic configuration for interactive visualisation (gene colours, etc.).

# Fields
- `geneColours::Dict{String, String}`: Maps gene UID to hex colour string for visualization
"""
@kwdef struct ScheduleVisMetadata
    geneColours::Dict{String, String} = Dict{String, String}()
end

"""
    Entity

Abstract base type for all entities in a network.

All Entity subtypes enforce a common interface:
- `uid::String`: Unique identifier within this network (for hierarchy references)
- `stateId::String`: Maps to FlatState counts (can collide across segments)
- `type::String`: Discriminator string ("species", "reaction", "gene", "differentiator")
- `parent::Union{String, Nothing}`: Optional parent uid for hierarchical relationships

The flat entity list with parent references enables simple traversal via
`filter(e -> e.parent == parent_uid, entities)` to find children.
"""
abstract type Entity end

"""
    SpeciesEntity

Represents a molecular species (gene product or intermediate).

# Fields
- `uid::String`: Unique identifier within this network
- `stateId::String`: FlatState mapping (e.g., "1_protein", "1_mrna")
- `type::String`: Always "species"
- `parent::Union{String, Nothing}`: Optional parent uid (e.g., gene uid if produced by that gene)
- `label::String`: Display name for visualization
"""
@kwdef struct SpeciesEntity <: Entity
    uid::String
    stateId::String
    type::String = "species"
    parent::Union{String, Nothing} = nothing
    label::String
end

"""
    ReactionEntity

Represents a reaction (mass action with kinetic rate).

Reactions are typically owned by a GeneEntity (via parent) and form part of the
transcription/translation/decay cascade. Can also be top-level when extracting from
other model types.

# Fields
- `uid::String`: Unique identifier within this network
- `stateId::Union{String, Nothing}`: Optional FlatState mapping if this reaction is tracked
- `type::String`: Always "reaction"
- `parent::Union{String, Nothing}`: Optional parent gene uid (e.g., gene uid for cascade reactions)
- `inputs::Vector{Dict}`: Reactants as `{speciesStateId, stoichiometry}` dicts
- `outputs::Vector{Dict}`: Products in same format
- `rate_forward::Float64`: Forward reaction rate
- `rate_reverse::Union{Float64, Nothing}`: Optional reverse rate for equilibrium reactions
"""
@kwdef struct ReactionEntity <: Entity
    uid::String
    stateId::Union{String, Nothing} = nothing
    type::String = "reaction"
    parent::Union{String, Nothing} = nothing
    inputs::Vector{Dict{String, Any}} = []  # {speciesStateId, stoichiometry}
    outputs::Vector{Dict{String, Any}} = []
    rate_forward::Float64
    rate_reverse::Union{Float64, Nothing} = nothing
end

"""
    GeneEntity

Represents a gene with its regulatory network and cascade reactions.

Genes own child ReactionEntities (transcription, translation, mRNA decay, protein decay).
Regulation edges represent transcriptional interactions with other genes.

# Fields
- `uid::String`: Unique identifier within this network
- `stateId::String`: FlatState mapping (e.g., "1" for gene 1)
- `type::String`: Always "gene"
- `parent::Union{String, Nothing}`: Can be nothing (top-level) or a differentiator uid
- `label::String`: Display name (e.g., "Gene 1")
- `baseRates::Dict{String, Float64}`: Base kinetic rates for the cascade
- `activation::Vector{Dict}`: Inbound transcriptional activation edges with fields:
  - `fromGeneId`: Regulating gene (protein product)
  - `at`: Binding affinity (molecules at half-saturation)
  - `k`: Hill coefficient (cooperativity)
- `repression::Vector{Dict}`: Inbound transcriptional repression edges (same format as activation)
- `proteolysis::Vector{Dict}`: Inbound proteolytic degradation edges with fields:
  - `fromGeneId`: Protease gene
  - `k`: Reaction rate constant
- `promoterInactiveId::String`: FlatState ID of inactive promoter state
- `promoterActiveId::String`: FlatState ID of active promoter state
- `proteinStateId::String`: FlatState ID of the protein species
- `mrnaStateId::String`: FlatState ID of the mRNA species (always present)
"""
@kwdef struct GeneEntity <: Entity
    uid::String
    stateId::String
    type::String = "gene"
    parent::Union{String, Nothing} = nothing
    label::String
    baseRates::Dict{String, Float64}

    # Regulation edges (owned by gene, reference by stateId)
    activation::Vector{Dict{String, Any}} = []  # {fromGeneId, at, k}
    repression::Vector{Dict{String, Any}} = []  # {fromGeneId, at, k}
    proteolysis::Vector{Dict{String, Any}} = []  # {fromGeneId, k}

    # Structure (FlatState IDs)
    promoterInactiveId::String
    promoterActiveId::String
    proteinStateId::String
    mrnaStateId::String
end

"""
    DifferentiatorEntity

Represents a cellular differentiation decision point in the schedule.

Differentiators are used in Models.Differentiation to create branching execution paths.
They can own child genes that are only expressed in certain branches.

# Fields
- `uid::String`: Unique identifier within this network
- `stateId::String`: FlatState mapping for differentiation state tracking
- `type::String`: Always "differentiator"
- `parent::Union{String, Nothing}`: Optional parent uid (another differentiator or scope)
- `label::String`: Display name (e.g., "Branch A")
- `branchInfo::Union{Dict, Nothing}`: Metadata about branches (e.g., branching probabilities)
"""
@kwdef struct DifferentiatorEntity <: Entity
    uid::String
    stateId::String
    type::String = "differentiator"
    parent::Union{String, Nothing} = nothing
    label::String
    branchInfo::Union{Dict{String, Any}, Nothing} = nothing
end

"""
    Network

A flat collection of entities representing molecular interactions at one timeline segment.

Stored as a flat array (not hierarchical tree) to simplify serialisation and traversal.
Hierarchical relationships encoded via `Entity.parent` references. All entities in a
network share the same simulation scope and time window.

# Fields
- `id::String`: Identifier for this network (typically the execution path)
- `entities::Vector{Entity}`: Flat list of all entities (genes, reactions, species, differentiators)
- `edges::Vector{Dict}`: Array of edges with fields:
  - `source::String`: Source entity uid
  - `target::String`: Target entity uid
  - `type::String`: Edge type ("input", "output", "activation", "repression", "proteolysis")
  - `affinity::Union{Float64, Nothing}`: Optional affinity/binding parameter
  - `hill::Union{Float64, Nothing}`: Optional Hill coefficient
"""
@kwdef struct Network
    id::String
    entities::Vector{Entity}
    edges::Vector{Dict{String, Any}} = []
end

"""
    TimelineSegment

Represents one execution segment within a schedule's timeline.

Maps one-to-one with a Primitive (unique path). Contains a snapshot of the network
at that execution point and the bindings applied.

# Fields
- `path::String`: Unique identifier encoding the execution path through the schedule AST
- `from::Float64`: Start time of this segment in simulation
- `to::Float64`: End time of this segment in simulation
- `network::Network`: Embedded network representation at this execution point
- `bindings::Dict{String, Any}`: Parameter bindings active during this segment
"""
@kwdef struct TimelineSegment
    path::String
    from::Float64
    to::Float64
    network::Network
    bindings::Dict{String, Any} = Dict()
end

"""
    ScheduleData

Complete visualization schema for schedule execution.

Contains the full execution timeline with embedded networks and visualization metadata.
Maps one-to-one to TypeScript ScheduleData for frontend visualization.

# Fields
- `segments::Vector{TimelineSegment}`: Execution timeline (one per execution path)
- `visMetadata::ScheduleVisMetadata`: Visualization configuration (gene colours, etc.)
"""
@kwdef struct ScheduleData
    segments::Vector{TimelineSegment}
    visMetadata::ScheduleVisMetadata = ScheduleVisMetadata()
end

# ============================================================================
# API Types
# ============================================================================

"""
    ValidationMessage

Single validation message for schedule (error, warning, or info).

# Fields
- `type::String`: Message type - \"error\", \"warning\", or \"info\"
- `content::String`: Message text
"""
@kwdef struct ValidationMessage
    type::String  # \"error\", \"warning\", or \"info\"
    content::String
end

"""
    ReifiedSchedule

Complete schedule representation with metadata and visualization data.

Represents a loaded schedule from storage (examples, user, or snapshot sources).
Combines schedule metadata with optional visualization data. "Reified" indicates
the schedule has been materialized from abstract specification into concrete
visualization-ready form with validation.

# Fields
- `name::String`: Schedule name/identifier
- `source::String`: Source location - \"examples\", \"user\", or \"snapshot\"
- `spec::String`: Original schedule specification as JSON string
- `data::Union{ScheduleData, Nothing}`: Parsed visualization data (null if parsing failed)
- `validationMessages::Vector{ValidationMessage}`: Validation errors, warnings, and info messages
"""
@kwdef struct ReifiedSchedule
    name::String
    source::String  # \"examples\", \"user\", or \"snapshot\"
    spec::String
    data::Union{ScheduleData, Nothing} = nothing
    validationMessages::Vector{ValidationMessage} = ValidationMessage[]
end

# ============================================================================
# Public API
# ============================================================================

"""
    reify_schedule(spec_string::String; name::String="", source::String="snapshot")::ReifiedSchedule

Parse, validate, and build visualization data for a schedule spec string.

Encapsulates the full pipeline: parse JSON → validate → generate visualization → return ReifiedSchedule object.
Validation is performed implicitly during construction.

# Arguments
- `spec_string::String`: Schedule specification as JSON string
- `name::String`: Schedule name/identifier (default: empty)
- `source::String`: Source location (default: "snapshot")

# Returns
- `ReifiedSchedule`: Complete schedule object with validation messages and visualization data
"""
function reify_schedule(spec_string::String; name::String="", source::String="snapshot")::ReifiedSchedule
    validation_messages = ValidationMessage[]
    visualization = nothing

    try
        # Parse spec
        spec = JSON.parse(spec_string, dicttype=Dict{Symbol, Any})

        # Validate by attempting construction
        validation_msgs = _validate_spec(spec)
        append!(validation_messages, validation_msgs)

        # Only generate visualization if no errors
        has_errors = any(m -> m.type == "error", validation_messages)
        if !has_errors
            try
                bindings = Dict(
                    :seed => get(spec, :seed, "default"),
                    :into => "",
                    :channel => "",
                    :defaults => Models.load_defaults(),
                )
                specification = Specifications.Specification(spec; bound = Set(keys(bindings)))
                grs_schedule = Models.Scheduling.Schedule(; specification, bindings)
                vis_data = generate_vis_data(grs_schedule, name)
                vis_metadata = isempty(vis_data.visMetadata.geneColours) ?
                    generate_default_vis_metadata(vis_data) :
                    vis_data.visMetadata
                visualization = ScheduleData(
                    segments = vis_data.segments,
                    visMetadata = vis_metadata
                )
            catch e
                push!(validation_messages, ValidationMessage(
                    type = "error",
                    content = "Failed to generate visualization: $(string(e))"
                ))
                @error "Failed to generate visualisation", e
            end
        end
    catch e
        # Parse error
        push!(validation_messages, ValidationMessage(
            type = "error",
            content = "Invalid JSON: $(string(e))"
        ))
    end

    return ReifiedSchedule(
        name = name,
        source = source,
        spec = spec_string,
        data = visualization,
        validationMessages = validation_messages
    )
end

"""
    is_valid(reified::ReifiedSchedule)::Bool

Check if a reified schedule is valid (has no error messages).

# Arguments
- `reified::ReifiedSchedule`: The reified schedule to check

# Returns
- `Bool`: True if valid (no error messages), false otherwise
"""
function is_valid(reified::ReifiedSchedule)::Bool
    return !any(msg -> msg.type == "error", reified.validationMessages)
end

"""
    get_error_messages(reified::ReifiedSchedule)::String

Get concatenated error messages from a reified schedule.

# Arguments
- `reified::ReifiedSchedule`: The reified schedule to extract errors from

# Returns
- `String`: Concatenated error messages separated by "; ", or empty string if no errors
"""
function get_error_messages(reified::ReifiedSchedule)::String
    error_msgs = filter(msg -> msg.type == "error", reified.validationMessages)
    return join([msg.content for msg in error_msgs], "; ")
end

"""
    extract_network(definition::V1.Definition)::Network

Extract genes, reactions, and regulation from V1 model definition.

Creates a flat entity list where:
- GeneEntity owns its reactions (via parent)
- ReactionEntity has parent pointing to its gene
- Reactions represent the transcription/translation/decay cascade

Public API for debugging and testing purposes.
"""
function extract_network(definition::V1.Definition)::Network
    entities = Entity[]

    # Extract genes
    for (gene_id, gene) in enumerate(definition.genes)
        gene_str = string(gene_id)
        gene_uid = "gene_$(gene_str)"

        # Create GeneEntity
        gene_entity = GeneEntity(
            uid = gene_uid,
            stateId = gene_str,
            type = "gene",
            parent = nothing,  # Top-level
            label = "Gene $gene_id",
            baseRates = Dict(
                "transcription" => gene.base_rates.transcription,
                "translation" => gene.base_rates.translation,
                "mrna_decay" => gene.base_rates.mrna_decay,
                "protein_decay" => gene.base_rates.protein_decay
            ),
            activation = _extract_regulation(gene.activation.slots),
            repression = _extract_regulation(gene.repression.slots),
            proteolysis = _extract_proteolysis(gene.proteolysis.slots),
            promoterInactiveId = "$(gene_str)_promoter_inactive",
            promoterActiveId = "$(gene_str)_promoter_active",
            proteinStateId = "$(gene_str)_protein",
            mrnaStateId = "$(gene_str)_mrna"
        )
        push!(entities, gene_entity)

        # Create reaction entities for this gene's cascade
        # Transcription reaction
        push!(entities, ReactionEntity(
            uid = "$(gene_uid)_transcription",
            stateId = nothing,
            type = "reaction",
            parent = gene_uid,
            inputs = [Dict("stateId" => "$(gene_str)_promoter_active", "stoichiometry" => 1)],
            outputs = [Dict("stateId" => "$(gene_str)_mrna", "stoichiometry" => 1)],
            rate_forward = gene.base_rates.transcription
        ))

        # Translation reaction
        push!(entities, ReactionEntity(
            uid = "$(gene_uid)_translation",
            stateId = nothing,
            type = "reaction",
            parent = gene_uid,
            inputs = [Dict("stateId" => "$(gene_str)_mrna", "stoichiometry" => 1)],
            outputs = [Dict("stateId" => "$(gene_str)_protein", "stoichiometry" => 1)],
            rate_forward = gene.base_rates.translation
        ))

        # mRNA decay
        push!(entities, ReactionEntity(
            uid = "$(gene_uid)_mrna_decay",
            stateId = nothing,
            type = "reaction",
            parent = gene_uid,
            inputs = [Dict("stateId" => "$(gene_str)_mrna", "stoichiometry" => 1)],
            outputs = [],
            rate_forward = gene.base_rates.mrna_decay
        ))

        # Protein decay
        push!(entities, ReactionEntity(
            uid = "$(gene_uid)_protein_decay",
            stateId = nothing,
            type = "reaction",
            parent = gene_uid,
            inputs = [Dict("stateId" => "$(gene_str)_protein", "stoichiometry" => 1)],
            outputs = [],
            rate_forward = gene.base_rates.protein_decay
        ))
    end

    # Build edges from entity relationships
    edges = _build_edges_from_entities(entities)

    return Network(id = "v1_network", entities = entities, edges = edges)
end

# ============================================================================
# Internal: Visualization Generation
# ============================================================================

"""
    generate_vis_data(grs_schedule, label::String="")::ScheduleData

Convert a GRS Schedule object to ScheduleData for visualization.

Returns a complete visualization schema with execution timeline and embedded networks.
Internal function used by reify_schedule.

# Arguments
- `grs_schedule`: GRS.Models.Scheduling.Schedule object
- `label::String`: Optional schedule name/identifier
"""
function generate_vis_data(grs_schedule, label::String="")::ScheduleData
    # Build timeline segments by reifying each execution path
    segments = _build_timeline_segments(grs_schedule)

    # Validate timeline continuity (strict check to prevent bugs)
    valid, errors = _validate_timeline_continuity(segments)
    if !valid
        @warn "Timeline continuity issues detected: $(join(errors, "; "))"
    end

    return ScheduleData(
        segments = segments,
        visMetadata = ScheduleVisMetadata()
    )
end

"""
    generate_default_vis_metadata(vis_data::ScheduleData)::ScheduleVisMetadata

Generate default visualization metadata (e.g., gene colours) from schedule data.

Assigns unique colours to each gene found in the network entities.
"""
function generate_default_vis_metadata(vis_data::ScheduleData)::ScheduleVisMetadata
    gene_colours = Dict{String, String}()

    # Extract unique genes from first segment
    if !isempty(vis_data.segments)
        genes = filter(e -> e isa GeneEntity, vis_data.segments[1].network.entities)

        # Generate distinguishable colour palette using Colors.jl
        if !isempty(genes)
            seed = [colorant"white", colorant"black", colorant"crimson"]
            colors = distinguishable_colors(length(genes), seed, dropseed = true)
            # Reduce saturation to make colours more pastel
            colors = [let hsv = HSV(c); HSV(hsv.h, hsv.s * 0.7, hsv.v * 1.3) end for c in colors]
            colors = convert.(RGB, colors)
            for (idx, gene) in enumerate(genes)
                color_hex = hex(colors[idx])
                gene_colours[gene.uid] = "#$color_hex"
            end
        end
    end

    return ScheduleVisMetadata(geneColours = gene_colours)
end

"""
    _build_edges_from_entities(entities::Vector{Entity})::Vector{Dict{String, Any}}

Extract edges from entity relationships.

Edges come from:
- Reactions: inputs/outputs create "input"/"output" edges to/from species
- Genes: activation/repression/proteolysis edges to target genes

# Returns
- `Vector{Dict}`: Array of edges with source, target, type, and optional parameters
"""
function _build_edges_from_entities(entities::Vector{Entity})::Vector{Dict{String, Any}}
    edges = Dict{String, Any}[]
    edge_set = Set{String}()

    for entity in entities
        if entity isa GeneEntity
            # Activation edges
            for act in entity.activation
                key = "$(act["fromGeneId"])→$(entity.uid):activation"
                if !in(key, edge_set)
                    push!(edge_set, key)
                    push!(edges, Dict(
                        "source" => act["fromGeneId"],
                        "target" => entity.uid,
                        "type" => "activation",
                        "affinity" => get(act, "at", nothing),
                        "hill" => get(act, "k", nothing)
                    ))
                end
            end

            # Repression edges
            for rep in entity.repression
                key = "$(rep["fromGeneId"])→$(entity.uid):repression"
                if !in(key, edge_set)
                    push!(edge_set, key)
                    push!(edges, Dict(
                        "source" => rep["fromGeneId"],
                        "target" => entity.uid,
                        "type" => "repression",
                        "affinity" => get(rep, "at", nothing),
                        "hill" => get(rep, "k", nothing)
                    ))
                end
            end

            # Proteolysis edges
            for prot in entity.proteolysis
                key = "$(prot["fromGeneId"])→$(entity.uid):proteolysis"
                if !in(key, edge_set)
                    push!(edge_set, key)
                    push!(edges, Dict(
                        "source" => prot["fromGeneId"],
                        "target" => entity.uid,
                        "type" => "proteolysis",
                        "affinity" => nothing,
                        "hill" => get(prot, "k", nothing)
                    ))
                end
            end
        elseif entity isa ReactionEntity
            # Input edges (reactants)
            for inp in entity.inputs
                stateId = get(inp, "stateId", nothing)
                if !isnothing(stateId)
                    key = "$stateId→$(entity.uid):input"
                    if !in(key, edge_set)
                        push!(edge_set, key)
                        push!(edges, Dict(
                            "source" => stateId,
                            "target" => entity.uid,
                            "type" => "input",
                            "affinity" => nothing,
                            "hill" => nothing
                        ))
                    end
                end
            end

            # Output edges (products)
            for out in entity.outputs
                stateId = get(out, "stateId", nothing)
                if !isnothing(stateId)
                    key = "$(entity.uid)→$stateId:output"
                    if !in(key, edge_set)
                        push!(edge_set, key)
                        push!(edges, Dict(
                            "source" => entity.uid,
                            "target" => stateId,
                            "type" => "output",
                            "affinity" => nothing,
                            "hill" => nothing
                        ))
                    end
                end
            end
        end
    end

    return edges
end

# ============================================================================
# Internal: Validation Helpers
# ============================================================================

"""
    _validate_spec(spec::Dict{Symbol, Any})::Vector{ValidationMessage}

Validate a schedule specification dictionary.

Uses GRS.jl's Models construction for comprehensive validation including:
- JSON structure validation
- Required fields
- Model type checking
- Semantic constraints

Internal function - validation messages returned for aggregation.
"""
function _validate_spec(spec::Dict{Symbol, Any})::Vector{ValidationMessage}
    messages = ValidationMessage[]

    # Check 1: Non-empty specification
    if isempty(spec)
        push!(messages, ValidationMessage(type="error", content="Schedule specification is empty"))
        return messages
    end

    # Check 2: Validate seed if present
    if haskey(spec, :seed)
        seed = spec[:seed]
        if !isa(seed, String)
            push!(messages, ValidationMessage(type="warning", content="Seed should be a string (got $(typeof(seed)))"))
        end
    else
        push!(messages, ValidationMessage(type="info", content="No seed specified (will use default)"))
    end

    # Check 3: Try to construct Model using GRS.jl's validation
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
        error_msg = string(e)
        push!(messages, ValidationMessage(type="error", content="Schedule validation failed: $error_msg"))
    end

    return messages
end

"""
    _validate_timeline_continuity(segments::Vector{TimelineSegment})::Tuple{Bool, Vector{String}}

Validate that timeline segments form a continuous progression without gaps or overlaps.

# Returns
- `Bool`: true if timeline is valid
- `Vector{String}`: error messages (empty if valid)
"""
function _validate_timeline_continuity(segments::Vector{TimelineSegment})::Tuple{Bool, Vector{String}}
    errors = String[]

    if isempty(segments)
        return (true, errors)
    end

    # Check 1: First segment starts at time zero
    if segments[1].from != 0.0
        push!(errors, "First timeline segment must start at time 0.0, got $(segments[1].from)")
    end

    # Check 2: All segments have positive duration
    for (idx, segment) in enumerate(segments)
        if segment.from >= segment.to
            push!(errors, "Segment $idx: invalid time range from=$(segment.from) to=$(segment.to)")
        end
    end

    # Check 3: No overlaps on same path
    path_segments = Dict{String, Vector{TimelineSegment}}()
    for seg in segments
        if !haskey(path_segments, seg.path)
            path_segments[seg.path] = TimelineSegment[]
        end
        push!(path_segments[seg.path], seg)
    end

    for (path, segs) in path_segments
        if length(segs) > 1
            sorted_segs = sort(segs, by = s -> s.from)
            for i in 1:length(sorted_segs)-1
                curr = sorted_segs[i]
                next_seg = sorted_segs[i+1]
                if curr.to > next_seg.from
                    push!(errors, "Segments on path '$path' overlap: [$(curr.from), $(curr.to)] and [$(next_seg.from), $(next_seg.to)]")
                end
            end
        end
    end

    return (isempty(errors), errors)
end

# ============================================================================
# Internal: Network Extraction Helpers
# ============================================================================

"""
    _extract_regulation(slots::Vector)::Vector{Dict{String, Any}}

Convert V1 HillRegulator slots to flat dictionaries.

# Returns
- `Vector{Dict}`: Array of {"fromGeneId" => ..., "at" => ..., "k" => ...} dicts
"""
function _extract_regulation(slots::Vector)::Vector{Dict{String, Any}}
    [Dict(
        "fromGeneId" => string(regulator.from),
        "at" => regulator.at,
        "k" => regulator.k
    ) for regulator in slots]
end

"""
    _extract_proteolysis(slots::Vector)::Vector{Dict{String, Any}}

Convert V1 DirectRegulator proteolysis slots to flat dictionaries.

# Returns
- `Vector{Dict}`: Array of {"fromGeneId" => ..., "k" => ...} dicts
"""
function _extract_proteolysis(slots::Vector)::Vector{Dict{String, Any}}
    [Dict(
        "fromGeneId" => string(regulator.from),
        "k" => regulator.k
    ) for regulator in slots]
end

# ============================================================================
# Internal: Timeline Building
# ============================================================================

"""
    _unwrap_definition(model)

Extract V1.Definition from a wrapped model, traversing nested Wrapped layers.

# Returns
- `V1.Definition` or `nothing` if no Definition found
"""
function _unwrap_definition(model)
    # Unwrap Wrapped layers
    while model isa Models.Wrapped
        inner = model.model
        if inner isa V1.Definition
            return inner
        end
        # Check if inner has a definition attribute
        if hasfield(typeof(inner), :definition)
            def = getfield(inner, :definition)
            if def isa V1.Definition
                return def
            end
        end
        model = inner
    end

    # Check if model itself has definition
    if hasfield(typeof(model), :definition)
        def = getfield(model, :definition)
        if def isa V1.Definition
            return def
        end
    end

    return nothing
end

"""
    _build_timeline_segments(grs_schedule)::Vector{TimelineSegment}

Create TimelineSegments from schedule primitives with correct timing and entities.

Algorithm:
1. Run dryrun to collect all dynamic model execution intervals
2. Extract Definition from each primitive via dryrun callback
3. Merge consecutive segments with identical definitions on same execution path
4. Create TimelineSegment for each merged interval with embedded Network

# Returns
- `Vector{TimelineSegment}`: Timeline segments in execution order
"""
function _build_timeline_segments(grs_schedule)::Vector{TimelineSegment}
    segments_data = []

    # Dryrun callback that collects segment timing and primitives
    function collect_segments(primitive!, x, Δt; path, _...)
        # Filter: only interested in callbacks with finite, positive Δt
        is_dynamic_interval = isfinite(Δt) && Δt > 0.0

        if !is_dynamic_interval
            return
        end

        model = primitive!.f!

        # Unwrap to get final model type
        while model isa Models.Wrapped
            model = model.model
        end

        # Only add non-Instant models
        if !(model isa Models.Instant)
            definition = _unwrap_definition(primitive!.f!)
            push!(segments_data, (path = path, from = x.t, to = x.t + Δt, definition = definition))
        end
    end

    # Run dryrun to traverse schedule
    @debug "build_timeline_segments: Starting dryrun"
    try
        state = Models.FlatState()
        grs_schedule(state; dryrun = collect_segments)
    catch e
        @debug "build_timeline_segments: Dryrun caught error: $(typeof(e)) - $(e)"
    end

    @debug "build_timeline_segments: Collected $(length(segments_data)) raw segments"

    if isempty(segments_data)
        return TimelineSegment[]
    end

    # Collate consecutive segments with identical definitions on same path
    merged_segments = []
    current_merge = nothing

    for seg in segments_data
        if isnothing(current_merge)
            current_merge = seg
        elseif (current_merge.definition == seg.definition) &&
               current_merge.to == seg.from &&
               current_merge.path == seg.path
            # Same definition, continuous time, same path → merge
            current_merge = (path = current_merge.path, from = current_merge.from, to = seg.to, definition = current_merge.definition)
        else
            # Different definition, gap, or different path → push current and start new
            push!(merged_segments, current_merge)
            current_merge = seg
        end
    end

    # Don't forget the last one
    if !isnothing(current_merge)
        push!(merged_segments, current_merge)
    end

    @debug "build_timeline_segments: After merging: $(length(merged_segments)) segments"

    if isempty(merged_segments)
        return TimelineSegment[]
    end

    # Extract first definition for network creation
    first_def = merged_segments[1].definition
    if isnothing(first_def) || isempty(first_def.genes)
        @debug "build_timeline_segments: First definition is nothing or has no genes"
        return TimelineSegment[]
    end

    @debug "build_timeline_segments: Definition has $(length(first_def.genes)) genes"

    # Extract network
    network = extract_network(first_def)
    @debug "build_timeline_segments: Extracted $(length(merged_segments)) timeline segments with $(length(network.entities)) total entities"

    # Create TimelineSegments from merged data
    segments = [
        TimelineSegment(
            path = data.path,
            from = data.from,
            to = data.to,
            network = network,
            bindings = Dict{String, Any}()
        )
        for data in merged_segments
    ]

    return segments
end

end # module ScheduleVisualization
