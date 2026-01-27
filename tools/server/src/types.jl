"""
    SchemaTypes

Registry of all types exported to TypeScript schema.

Re-exports all entity, network, and simulation types from their source modules
and provides a list of exportable types for automated schema generation.

This is the single source of truth for all types that should be synced to the
TypeScript frontend. Add any new public types to EXPORTABLE_TYPES.
"""
module SchemaTypes

# Import types from ScheduleVisualization module
import ..ScheduleVisualization: Entity, SpeciesEntity, ReactionEntity,
                                GeneEntity, DifferentiatorEntity,
                                Network, TimelineSegment, ScheduleData,
                                ScheduleVisMetadata, ValidationMessage,
                                ReifiedSchedule

# Import types from Simulation module
import ..Simulation: SimulationFrame, SimulationData, SimulationResultMetadata, SimulationResult

# Re-export all types for public API
export Entity, SpeciesEntity, ReactionEntity, GeneEntity, DifferentiatorEntity
export Network, TimelineSegment, ScheduleData, ScheduleVisMetadata
export ValidationMessage
export ReifiedSchedule
export SimulationFrame, SimulationData
export SimulationResultMetadata, SimulationResult

# ============================================================================
# Schema Registry
# ============================================================================

"""
    EXPORTABLE_TYPES

List of all types to be exported to TypeScript schema.

Used by schema generation tools to automatically extract type definitions
and generate TypeScript interfaces. When adding new public types to the server,
add them to this list to ensure they are synced to the frontend.

# Order

Types are ordered by category:
1. Entity base type and subtypes
2. Network and timeline types
3. Schedule and visualization types
4. Validation
5. Simulation types
"""
const EXPORTABLE_TYPES = [
    # Entity types (hierarchy in order: base, then subtypes)
    Entity,
    SpeciesEntity,
    ReactionEntity,
    GeneEntity,
    DifferentiatorEntity,

    # Network and timeline types
    Network,
    TimelineSegment,

    # Schedule and visualization
    ScheduleVisMetadata,
    ScheduleData,
    ReifiedSchedule,

    # Validation
    ValidationMessage,

    # Simulation types
    SimulationFrame,
    SimulationData,
    SimulationResultMetadata,
    SimulationResult,
]

end # module SchemaTypes
