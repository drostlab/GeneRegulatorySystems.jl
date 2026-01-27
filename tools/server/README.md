# GeneRegulatorySystems Server

An HTTP server for interactive scheduling and simulation of gene regulatory systems. Provides real-time visualization of stochastic simulations with a focus on cellular differentiation and branching dynamics.

## Quick Start

### Prerequisites
- Julia 1.9+ (check with `julia --version`)
- GeneRegulatorySystems.jl installed

### Running the Server

```bash
cd tools/server
julia --project=. run.jl
```

Server starts on `http://127.0.0.1:8000` by default.

**Custom host/port:**
```bash
julia --project=. run.jl 0.0.0.0 3000
```

## API Reference

All endpoints return JSON. Base URL: `http://localhost:8000/api`

### Schedule Management

#### List Available Example Schedules
```
GET /schedules/available
```
Returns all `.schedule.json` files from the embedded examples directory.

**Response:**
```json
{
  "schedules": [
    "toy/repressilator.schedule.json",
    "toy/cascade.schedule.json",
    "specification/minimal.schedule.json",
    ...
  ]
}
```

#### Load Schedule from Examples
```
GET /schedules/load?name=toy/repressilator.schedule.json
```
Load a pre-packaged example schedule. The server stores loaded schedules in memory and returns a schedule ID for later reference.

**Response:**
```json
{
  "id": "sched_1234567890",
  "name": "toy/repressilator.schedule.json",
  "loaded": true
}
```

#### Upload Custom Schedule
```
POST /schedules/upload
Content-Type: application/json

{
  "specification": { ... },
  "defaults": { ... }
}
```
Parse and load a custom schedule JSON specification.

**Response:**
```json
{
  "id": "sched_1234567890",
  "uploaded": true
}
```

#### Validate Schedule
```
POST /schedules/validate
Content-Type: application/json

{
  "specification": { ... }
}
```
Validate a schedule without loading/executing it. Returns parse errors, warnings, and info messages.

**Response:**
```json
{
  "valid": true,
  "errors": [],
  "warnings": ["Warning message"],
  "info": ["Info message"]
}
```

### Visualization Schema

#### Generate Schedule Schema
```
POST /schedules/schema
Content-Type: application/json

{
  "schedule_id": "sched_1234567890"
}
```
Generate the visualization schema for a loaded schedule. This describes:
- Network entities (genes, species, reactions)
- Timeline segments with execution paths
- Entity relationships and regulation edges

**Response:**
```json
{
  "segments": [
    {
      "path": "0",
      "from": 0.0,
      "to": 100.0,
      "network": { "entities": [...] }
    },
    {
      "path": "0/0",
      "from": 100.0,
      "to": 200.0,
      "network": { "entities": [...] }
    }
  ]
}
```

### Simulation Execution

#### Run Simulation (Non-streaming)
```
GET /simulations/run
```
Execute a schedule and return all collected frames immediately. Useful for small simulations.

**Query Parameters:**
- `schedule_id`: ID of loaded schedule (required)

**Response:**
```json
{
  "id": "sim_1234567890",
  "status": "completed",
  "frame_count": 15234,
  "result_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

#### Run Simulation (With WebSocket Streaming)
```
GET /simulations/stream
WebSocket: /ws/sim/{sim_id}
```
Start a simulation and stream frames in real-time to connected WebSocket clients.

**Frame Format (WebSocket):**
Each frame is a JSON object sent as the simulation progresses:
```json
{
  "type": "frame",
  "path": "0/1",
  "t": 45.32,
  "counts": {
    "Gene1_protein": 23,
    "Gene2_mrna": 5
  }
}
```

Completion message:
```json
{
  "type": "complete",
  "status": "completed",
  "frame_count": 15234,
  "result_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

### Results Storage & Retrieval

#### List All Results
```
GET /results/list
```
Get metadata for all stored simulation results.

**Response:**
```json
{
  "results": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "created_at": "2025-11-20T15:32:10.123Z",
      "status": "completed",
      "frame_count": 15234
    }
  ]
}
```

#### Get Result Metadata
```
GET /results/{result_id}/metadata
```
Retrieve metadata for a specific result.

#### Load Result Frames
```
GET /results/{result_id}/frames
```
Load all frames from a stored result (returns Arrow or JSON).

#### Delete Result
```
DELETE /results/{result_id}
```
Remove a stored result and its data files.

## Schedule Specification

Schedules are JSON files describing the temporal structure of simulations. Key sections:

```json
{
  "specification": {
    "do": "Model or nested specification",
    "for": 1000.0,
    "each": [
      { "specification": {...} },
      { "specification": {...} }
    ]
  },
  "defaults": {
    "network": {
      "entities": [...],
      "relationships": [...]
    }
  },
  "seed": "optional-seed-string"
}
```

### Built-in Examples

The server includes example schedules in `examples/`:

| Directory | Purpose |
|-----------|---------|
| `toy/` | Simple demos (repressilator, cascade, ACDC, etc.) |
| `specification/` | Feature demonstrations (templates, channels, etc.) |
| `benchmark/` | Performance test cases |

Load any example with: `GET /schedules/load?name=toy/repressilator.schedule.json`

## Data Format

### Simulation Frame

```julia
@kwdef struct SimulationFrame
    path::String              # Execution path (e.g., "0/1/2")
    t::Float64                # Time at this event
    counts::Dict{String,Int}  # Only changed species in this event
end
```

**Path Encoding:**
- `/` separates branch points (parallel execution)
- `-` separates sequential steps
- Digits are indices (e.g., `0/1/2` = branch 0, sub-branch 1, step 2)

Each frame only contains species that changed in that event. For a system with 50 species, typically only 2-3 are in each frame (~100 bytes). The frontend accumulates changes across frames to reconstruct the full state.

### Timeline Segment

```julia
@kwdef struct TimelineSegment
    path::String                          # Unique execution path through schedule AST
    from::Float64                         # Start time of segment
    to::Float64                           # End time of segment
    network::Network                      # Embedded network at this execution point
    bindings::Dict{String, Any}           # Parameter bindings active during this segment
end
```

Multiple segments at the same `from` time indicate parallel branches (differentiation events).

### Network

```julia
@kwdef struct Network
    id::String                # Network identifier
    entities::Vector{Entity}  # All entities (genes, species, reactions)
end
```

### Entity Types

Entities represent biological components. All inherit from abstract type `Entity`:

**SpeciesEntity** - A molecular species:
```julia
@kwdef struct SpeciesEntity <: Entity
    uid::String                           # Unique identifier within network
    stateId::String                       # Maps to FlatState counts (e.g., "1_protein")
    type::String = "species"              # Always "species"
    parent::Union{String, Nothing}        # Optional parent gene uid
    label::String                         # Display name
end
```

**ReactionEntity** - A mass action reaction:
```julia
@kwdef struct ReactionEntity <: Entity
    uid::String                           # Unique identifier
    stateId::Union{String, Nothing}       # Optional FlatState mapping
    type::String = "reaction"             # Always "reaction"
    parent::Union{String, Nothing}        # Optional parent gene uid
    inputs::Vector{Dict{String, Any}}     # Reactants: {stateId, stoichiometry}
    outputs::Vector{Dict{String, Any}}    # Products: {stateId, stoichiometry}
    rate_forward::Float64                 # Forward reaction rate
    rate_reverse::Union{Float64, Nothing} # Optional reverse rate
end
```

**GeneEntity** - A gene with regulatory network:
```julia
@kwdef struct GeneEntity <: Entity
    uid::String                           # Unique identifier
    stateId::String                       # Maps to FlatState (e.g., "1")
    type::String = "gene"                 # Always "gene"
    parent::Union{String, Nothing}        # Optional parent differentiator uid
    name::String                          # Display name
    baseRates::Dict{String, Float64}      # Base kinetic rates for cascade
    activation::Vector{Dict{String, Any}} # Activation edges: {fromGeneId, at, k}
    repression::Vector{Dict{String, Any}} # Repression edges: {fromGeneId, at, k}
    proteolysis::Vector{Dict{String, Any}}# Proteolysis edges: {fromGeneId, k}
    promoterInactiveId::String            # Inactive promoter state ID
    promoterActiveId::String              # Active promoter state ID
    proteinStateId::String                # Protein species state ID
    mrnaStateId::String                   # mRNA species state ID (always present)
end
```

**Regulation Fields:**
- `fromGeneId`: Which gene is doing the regulating (protein product)
- `at`: Binding affinity (molecules at half-saturation for Hill equation)
- `k`: Hill coefficient for activation/repression (cooperativity parameter); for proteolysis, reaction rate constant


### Schedule Schema

Complete visualization schema for a schedule:

```julia
@kwdef struct ScheduleSchema
    segments::Vector{TimelineSegment}                    # Execution timeline
    layout::Dict{String, Point}                         # Global entity positions
end
```

### Validation Result

Result of schedule validation:

```julia
@kwdef struct ValidationResult
    valid::Bool                           # Whether validation passed
    errors::Vector{String}                # Fatal errors
    warnings::Vector{String}              # Non-fatal warnings
    info::Dict{String, Any}               # Metadata about schedule
end
```

