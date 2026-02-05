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
using GeneRegulatorySystems.Models.NetworkRepresentation
using GeneRegulatorySystems.Specifications
using JSON
using Colors

# ============================================================================
# Exports
# ============================================================================

# Schema types (frontend contract)
export Network
export TimelineSegment, ScheduleData, ScheduleVisMetadata

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

# Fields
- `geneColours::Dict{String, String}`: Maps gene name to hex colour string
"""
@kwdef struct ScheduleVisMetadata
    geneColours::Dict{String, String} = Dict{String, String}()
end

"""
    Network

Flat network representation for visualization.

Uses NetworkRepresentation.Node and NetworkRepresentation.Link directly.

# Fields
- `nodes::Vector{NetworkRepresentation.Node}`: Flat list of all nodes
- `links::Vector{NetworkRepresentation.Link}`: Flat list of all links
"""
@kwdef struct Network
    nodes::Vector{NetworkRepresentation.Node}
    links::Vector{NetworkRepresentation.Link}
end

"""
    TimelineSegment

Execution segment within a schedule's timeline.

# Fields
- `path::String`: Unique execution path identifier
- `from::Float64`: Start time
- `to::Float64`: End time
- `bindings::Dict{String, Any}`: Parameter bindings during this segment
"""
@kwdef struct TimelineSegment
    path::String
    from::Float64
    to::Float64
    bindings::Dict{String, Any} = Dict()
end

"""
    ScheduleData

Complete visualization schema for schedule execution.

Contains network shared across all segments, execution timeline, and visualization metadata.
Maps one-to-one to TypeScript ScheduleData for frontend visualization.

# Fields
- `network::Network`: Shared network (nodes and links) across all segments
- `segments::Vector{TimelineSegment}`: Execution timeline (one per execution path)
- `visMetadata::ScheduleVisMetadata`: Visualization configuration (gene colours, etc.)
"""
@kwdef struct ScheduleData
    network::Network
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
    start_time = time()
    validation_messages = ValidationMessage[]
    visualization = nothing

    try
        # Parse spec
        parse_start = time()
        spec = JSON.parse(spec_string, dicttype=Dict{Symbol, Any})
        parse_time = time() - parse_start
        @info "Schedule parsed" name source parse_time

        # Validate by attempting construction
        validation_msgs = _validate_spec(spec)
        append!(validation_messages, validation_msgs)

        # Only generate visualization if no errors
        has_errors = any(m -> m.type == "error", validation_messages)
        if !has_errors
            try
                @info "Starting schedule visualization generation" name source
                vis_start = time()
                bindings = Dict(
                    :seed => get(spec, :seed, "default"),
                    :into => "",
                    :channel => "",
                    :defaults => Models.load_defaults(),
                )
                specification = Specifications.Specification(spec; bound = Set(keys(bindings)))
                grs_schedule = Models.Scheduling.Schedule(; specification, bindings)
                vis_data = generate_vis_data(grs_schedule, name)
                vis_time = time() - vis_start
                @info "Schedule visualization generated" name source vis_time segments=length(vis_data.segments)
                vis_metadata = isempty(vis_data.visMetadata.geneColours) ?
                    generate_default_vis_metadata(vis_data) :
                    vis_data.visMetadata
                visualization = ScheduleData(
                    network = vis_data.network,
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

    total_time = time() - start_time
    @info "Schedule load completed" name source valid=is_valid(ReifiedSchedule(name=name, source=source, spec=spec_string, validationMessages=validation_messages)) total_time

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
    extract_network(schedule::Scheduling.Schedule)::NetworkRepresentation.Entity

Extract network entity tree from schedule via dryrun.

Uses the NetworkCreation.entity() dispatch to handle all model types polymorphically.
Extracts the network from the first dynamic primitive encountered during dryrun.

# Returns
- `NetworkRepresentation.Entity`: Hierarchical entity tree with nodes and links
"""
function extract_network(schedule::Scheduling.Schedule)
    network = nothing

    function dryrun_collector(primitive!, x, Δt; path, _...)
        if !(isfinite(Δt) && Δt > 0.0)
            return
        end
        if network === nothing
            network = NetworkRepresentation.entity(primitive!)
        end
    end

    schedule(Models.FlatState(); dryrun=dryrun_collector)
    return network
end

# ============================================================================
# Internal: Visualization Generation
# ============================================================================

"""
    generate_vis_data(grs_schedule, label::String="")::ScheduleData

Convert a GRS Schedule object to ScheduleData for visualization.

Returns a complete visualization schema with shared network and timeline segments.
Internal function used by reify_schedule.

# Arguments
- `grs_schedule`: GRS.Models.Scheduling.Schedule object
- `label::String`: Optional schedule name/identifier
"""
function generate_vis_data(grs_schedule, label::String="")::ScheduleData
    # Build timeline segments and extract shared network
    network, segments = _build_timeline_segments(grs_schedule)

    # Validate timeline continuity (strict check to prevent bugs)
    valid, errors = _validate_timeline_continuity(segments)
    if !valid
        @warn "Timeline continuity issues detected: $(join(errors, "; "))"
    end

    return ScheduleData(
        network = network,
        segments = segments,
        visMetadata = ScheduleVisMetadata()
    )
end

"""
    generate_default_vis_metadata(vis_data::ScheduleData)::ScheduleVisMetadata

Generate default visualization metadata (gene colours) from schedule data.

Assigns unique colours to each gene found in the shared network.
"""
function generate_default_vis_metadata(vis_data::ScheduleData)::ScheduleVisMetadata
    gene_colours = Dict{String, String}()

    # Extract genes from shared network
    network = vis_data.network
    genes = filter(n -> n.kind == :gene, network.nodes)

    # Generate distinguishable colour palette
    if !isempty(genes)
        seed = [colorant"white", colorant"black", colorant"crimson"]
        colors = distinguishable_colors(length(genes), seed, dropseed = true)
        colors = [let hsv = HSV(c); HSV(hsv.h, hsv.s * 0.7, hsv.v * 1.3) end for c in colors]
        colors = convert.(RGB, colors)
        for (idx, gene) in enumerate(genes)
            color_hex = hex(colors[idx])
            gene_colours[string(gene.name)] = "#$color_hex"
        end
    end

    return ScheduleVisMetadata(geneColours = gene_colours)
end

# ============================================================================
# Internal: Validation Helpers
# ============================================================================

"""
    _validate_spec(spec::Dict{Symbol, Any})::Vector{ValidationMessage}

Validate a schedule specification dictionary.

# Returns
- `Vector{ValidationMessage}`: Validation messages
"""
function _validate_spec(spec::Dict{Symbol, Any})::Vector{ValidationMessage}
    messages = ValidationMessage[]

    if isempty(spec)
        push!(messages, ValidationMessage(type="error", content="Schedule specification is empty"))
        return messages
    end

    if haskey(spec, :seed)
        seed = spec[:seed]
        if !isa(seed, String)
            push!(messages, ValidationMessage(type="warning", content="Seed should be a string (got $(typeof(seed)))"))
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
        error_msg = string(e)
        push!(messages, ValidationMessage(type="error", content="Schedule validation failed: $error_msg"))
    end

    return messages
end

"""
    _validate_timeline_continuity(segments::Vector{TimelineSegment})::Tuple{Bool, Vector{String}}

Validate timeline segments form a continuous progression.

# Returns
- `Bool`: true if valid
- `Vector{String}`: error messages
"""
function _validate_timeline_continuity(segments::Vector{TimelineSegment})::Tuple{Bool, Vector{String}}
    errors = String[]

    if isempty(segments)
        return (true, errors)
    end

    if segments[1].from != 0.0
        push!(errors, "First timeline segment must start at time 0.0, got $(segments[1].from)")
    end

    for (idx, segment) in enumerate(segments)
        if segment.from >= segment.to
            push!(errors, "Segment $idx: invalid time range from=$(segment.from) to=$(segment.to)")
        end
    end

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

"""
    _build_timeline_segments(grs_schedule)::Tuple{Network, Vector{TimelineSegment}}

Create timeline segments and extract shared network from schedule via dryrun.

Extracts network entity from first dynamic primitive, flattens it once, and creates
lightweight timeline segments for all execution intervals.

# Returns
- `Tuple{Network, Vector{TimelineSegment}}`: Shared network and timeline segments
"""
function _build_timeline_segments(grs_schedule)::Tuple{Network, Vector{TimelineSegment}}
    segments_data = []

    # Dryrun callback that collects segment timing and primitives
    function collect_segments(primitive!, x, Δt; path, _...)
        if !(isfinite(Δt) && Δt > 0.0)
            return
        end

        model = primitive!.f!
        while model isa Models.Wrapped
            model = model.model
        end

        if !(model isa Models.Instant)
            push!(segments_data, (path = path, from = x.t, to = x.t + Δt, primitive = primitive!))
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

    # Extract network entity from first primitive
    network_entity = NetworkRepresentation.entity(segments_data[1].primitive)

    if network_entity === nothing
        @debug "build_timeline_segments: Could not extract network entity from first primitive"
        return TimelineSegment[]
    end

    @debug "build_timeline_segments: Extracted network entity with $(length(network_entity.nodes)) child nodes"

    # Flatten the network entity tree
    nodes_flat, links_flat = NetworkRepresentation.flatten(network_entity)
    flat_network = Network(nodes=nodes_flat, links=links_flat)
    @debug "build_timeline_segments: Flattened network has $(length(flat_network.nodes)) nodes and $(length(flat_network.links)) links"

    # Create TimelineSegments from collected data without embedding network
    segments = [
        TimelineSegment(
            path = data.path,
            from = data.from,
            to = data.to,
            bindings = Dict()
        )
        for data in segments_data
    ]

    return (flat_network, segments)
end

end # module ScheduleVisualization
