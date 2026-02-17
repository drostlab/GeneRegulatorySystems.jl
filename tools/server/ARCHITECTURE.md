# Server Architecture

## Backend (Julia)

| File | Purpose | Key Exports |
| ------ | --------- | ------------- |
| `src/server.jl` | HTTP route definitions (Oxygen.jl) | Routes: schedules CRUD, `POST /schedules/union-network`, `POST /schedules/network`, `POST /simulations/{id}/timeseries` (filtered), simulation run/results |
| `src/schedule_visualisation.jl` | Schedule reification, network extraction, structure tree | Types: `Network`, `UnionNetwork`, `ModelExclusions`, `TimelineSegment`, `StructureNode`, `ScheduleData`, `ReifiedSchedule`, `ValidationMessage`. Functions: `reify_schedule`, `extract_network_for_model_path`, `extract_union_network`. Internal: `_gene_names` (lightweight dispatch-based gene extraction without building networks), `_spec_bindings`/`_spec_seed` (handle both Dict and Vector specs), `_validate_spec` (Dict and Vector overloads), `_label`/`_type_label` (label extraction with fallback for unlabelled models) |
| `src/schedule_storage.jl` | Schedule file persistence (examples/user/snapshot) | `list_schedules`, `load_schedule`, `save_schedule` |
| `src/simulation.jl` | Simulation execution and result management | `run_simulation`, `load_result`, `list_results`, `load_timeseries_for_species` |
| `src/simulation_controller.jl` | Live simulation lifecycle (pause/resume, WS streaming, gene subscriptions) | `SimulationController`, `check_pause!`, `pause!`, `resume!`, `subscribe_genes!`, `send_progress`, `send_timeseries`, `send_status` |
| `src/streaming_sink.jl` | Arrow IPC storage + WS streaming during execution | `StreamingSimulationSink`, `flush!` |

## Frontend (Vue 3 + Pinia + SciChart + Cytoscape)

### Stores

| File | Purpose | Key State/Actions |
| ------ | --------- | ------------------- |
| `scheduleStore.ts` | Schedule data, union network | State: `schedule`, `unionNetwork`, `isLoading`, `isNetworkLoading`. Computed: `allGenes`, `geneColours`, `segments`, `modelPaths`. Actions: `loadScheduleByKey`, `loadScheduleBySpec`, `fetchUnionNetwork`, `clearNetwork`. Spec-skip: compares new spec to current before reloading. |
| `viewerStore.ts` | All selection/interaction state | State: `currentTimepoint`, `selectedGenes`, `selectedSpeciesTypes`, `selectedSegmentIds`. Computed: `activeModelPath` (derived from currentTimepoint + segments), `selectedPaths`, `proteinCountsAtTimepoint`, `maxProteinCounts`. Actions: `selectSegments` |
| `simulationStore.ts` | Simulation results with lazy loading + streaming | State: `currentResult` (`SimulationResult | null`), `isSimulationRunning`, `isPaused`, `timeseriesCache`, `fetchedGenes`, `streamingBuffer`. Computed: `timeseries`, `progress`, `currentResultId`, `currentResultLabel`. Actions: `runSimulation`, `loadResult`, `fetchGeneTimeseries(genes)`, `getTimeseries(genes?, paths?)`, `pauseSimulation`, `resumeSimulation`, `updateStreamSubscription(genes)` |

### Charts (SciChart)

| File | Purpose |
| ------ | --------- |
| `MainChart.ts` | Orchestrates all panels. Creates `SeriesSyncCoordinator` with gene grouping function and passes it to panels via `BasePanelOptions`. Callbacks: `onTimepointChange`, `onSelectionChange`, `onSegmentClick`. |
| `SeriesSyncCoordinator.ts` | Syncs hover state across subcharts by group key. Dims non-hovered series (opacity=0.3), skips null-group (segments). Invalidates parent surface after sync. Reentrancy-guarded. |
| `panels/BasePanel.ts` | Abstract base: surface, wasmContext, coordinator, visibility, `setTimeExtent` |
| `panels/TimeseriesPanel.ts` | Abstract: adds `metadata`, `pathTimeRanges`, abstract `setData`, `appendStreamingData`, `clearData` |
| `panels/TimelinePanel.ts` | FastRectangleRenderableSeries for schedule segments. Path-only labels (small font). Hover tooltip shows label+path+model. Instant labels stacked at top. Click fires segment callback. |
| `panels/PromoterPanel.ts` | FastBandRenderableSeries for promoter activity, positioned by `pathYRanges`. Hover dims via coordinator. Streaming: `appendStreamingData` with cursor extension for XyyDataSeries. SweepAnimation on `setData`. |
| `panels/CountsPanel.ts` | FastLineRenderableSeries for mRNA/protein counts. Hover dims via coordinator. Streaming: `appendStreamingData` with cursor extension for XyDataSeries. SweepAnimation on `setData`. |
| `charts/chartConstants.ts` | Centralised font family, font sizes, axis thickness, and segment palette |
| `layout/rectangleLayout.ts` | `layoutRectangles(structure, segments, yMin, yMax)` and `collectPathYRanges` |
| `modifiers/AxisSyncModifier.ts` | Syncs X-axis visible range across sub-charts |
| `modifiers/SelectSyncModifier.ts` | Syncs selection by group key across sub-charts. Accepts generic `GroupingFn`. Scans subcharts directly (no cache). |
| `modifiers/SharedTimeCursorModifier.ts` | Vertical cursor line synced across sub-charts |
| `modifiers/SubChartLayoutModifier.ts` | Vertical stacking of visible sub-charts |

### Network (Cytoscape)

| File | Purpose |
| ------ | --------- |
| `network/NetworkView.ts` | Orchestrator. Owns Cytoscape instance, lifecycle. Creates and coordinates sub-modules. Uses `layoutstop` event (not timeout). Layout: fcose with nodeRepulsion=50000, idealEdgeLength=100, edgeElasticity=0.8, numIter=5000. |
| `network/networkElements.ts` | `convertGeneElements(union, geneColours)` for gene-level view. `getDetailElements()` for species (with compound parent) + reactions. Filters `MODEL_NODE_KINDS` and `MACHINERY_SPECIES`. |
| `network/networkStyles.ts` | `buildStylesheet()` returns Cytoscape style array. `.excluded { display: none }` for ModelFilter. Compound parent selector `$node > node` for gene label positioning. Self-loop edge style. |
| `network/AdaptiveZoom.ts` | Zoom threshold (1.2). Below: genes only. Above: adds species as compound children of genes (positioned in tight grid), reactions near neighbours. 50ms debounce. Fires `onDetailChange` callback. |
| `network/ModelFilter.ts` | Watches `viewerStore.activeModelPath`. Toggles `.excluded` CSS class on nodes/edges (no add/remove, avoids conflicts with AdaptiveZoom). |
| `network/SelectionSync.ts` | Two-way sync: `viewerStore.selectedGenes` <-> Cytoscape node tap. Multi-select: click toggles gene in/out of selection. Highlights selected, dims others. |
| `network/DynamicsSync.ts` | Watches `viewerStore.proteinCountsAtTimepoint` + `selectedGenes`. Only resizes selected genes (80-250 x 40-100); unselected stay at base size. Debounced at 16ms. |
| `network/EdgeTooltip.ts` | Edge hover tooltip showing link kind. Lightweight DOM element positioned at cursor. |

### Data Flow

1. Schedule loaded -> `scheduleStore.loadScheduleByKey/Spec` -> server returns `ScheduleData` (segments, structure, genes, gene_colours, no network)
2. `TrackViewer` watches schedule data -> `MainChart.setScheduleData` -> `TimelinePanel` computes layout rectangles -> `collectPathYRanges` passed to `PromoterPanel`. Then calls `scheduleStore.fetchUnionNetwork()` which eagerly fetches union of all models.
3. `NetworkDiagram` watches `scheduleStore.unionNetwork` -> `NetworkView.setNetwork()` -> renders gene-level graph -> fcose layout runs once -> sub-modules attach: `ModelFilter` hides excluded nodes for first model, `SelectionSync` + `DynamicsSync` start watching.
4. Simulation loaded -> `simulationStore.loadResult` loads metadata only. `selectedGenes` watcher triggers `fetchGeneTimeseries(genes)` which lazily loads per-gene timeseries via `POST /simulations/{id}/timeseries`. After fetch -> `refreshSimulationData()` pushes to chart with `SweepAnimation`.
5. Gene selection: click on series (chart) -> `viewerStore.selectedGenes` updates -> lazy fetch for new genes -> `SelectionSync` highlights in network. Click on gene node (network) -> same flow.
6. `activeModelPath` is a computed derived from `currentTimepoint` + segments. As time cursor moves, model filter updates automatically.
7. Zoom in past threshold -> `AdaptiveZoom` adds species/reaction nodes (gene positions pinned) -> `ModelFilter.refresh()` + `SelectionSync.refresh()`.

### Simulation Streaming

**Backend flow:**
1. `POST /simulations/run` creates a `SimulationController` and stores it as `active_controller`. Returns immediately with `status=running`.
2. `StreamingSimulationSink` receives every simulation event. It writes Arrow IPC to disk, and if the controller has subscribed species, accumulates timeseries data per species/path.
3. At time-window intervals (`stream_interval = 200.0` sim-time units), the sink sends a `progress` message and a `timeseries` batch to the WS client via the controller.
4. When the simulation completes, the sink sends a final `status: completed` message.

**WS protocol** (`/ws`):
- Client -> Server: `{ type: "subscribe", species: [...] }`, `{ type: "pause" }`, `{ type: "resume" }`
- Server -> Client: `{ type: "progress", simulation_id, current_time, frame_count }`, `{ type: "timeseries", simulation_id, data: TimeseriesData }`, `{ type: "status", simulation_id, status, error? }`

**Pause/resume:** `check_pause!(controller)` is called on every sink event. When paused, the simulation thread blocks on a `Threads.Condition`. Resume notifies the condition.

**Frontend flow:**
1. `simulationStore.runSimulation()` connects the WS via `useSimulationStream`, tracks the simulation ID, and subscribes the first N selected genes.
2. WS `progress` callbacks update `currentResult.current_time`; `streamingDelta` holds the latest timeseries batch (not cumulative).
3. `TrackViewer.vue` watches `streamingDelta` with RAF throttle, calling `MainChart.appendStreamingData(data, currentTime)` which routes to `CountsPanel` / `PromoterPanel`. During streaming, the timeseries cache watcher is skipped (`isSimulationRunning` guard) to prevent `setData` from overwriting incremental appends.
4. Each panel maintains a `seriesMap` of persistent `XyDataSeries` / `XyyDataSeries` and a **trailing cursor extension point**: a temporary last point at `min(currentTime, pathEndTime)` with the last known value. Cursor points are clamped to the path's time range via `pathTimeRanges` (computed from segments by `getPathTimeRanges`) so they don't extend into later segments.
5. `PromoterPanel` pre-computes band layout params (yCenter, bandHeight) for every (gene, path) key when `setPathYRanges` or `setMetadata` is called, so streaming doesn't need to guess band dimensions.
6. Progress-driven time cursor sync moves `viewerStore.currentTimepoint` during simulation.
7. On completion, the store clears the streaming cache and refetches definitive timeseries via HTTP. `setData` renders the complete result with `SweepAnimation`.

### Loading UX Pattern

Two overlay classes:
- `.disabled-overlay`: dim, no spinner, pointer-events disabled. Used when a component is waiting for an earlier loading stage.
- `.loading-overlay` + `.loading-card`: dim with centred spinner + text. Used when that component's data is actively being fetched.

Schedule change stages:
1. Editor clears content, shows "Validating schedule..." spinner overlay. Chart and network show `.disabled-overlay` (old content visible, dimmed).
2. When validation returns, editor updates. Chart/network get new data; old content replaced.
3. Network fetch fires non-blocking after schedule data arrives. Network shows spinner only during `isNetworkLoading`.

Simulation timeseries: first-ever fetch shows full overlay on chart; subsequent gene selections show spinner in MultiSelect only.

### Key Naming Convention

`dataSeriesName` format: `{geneId}:{executionPath}` for timeseries, `segment:{segmentId}` for timeline rectangles. Sync modifiers extract gene ID as prefix before `:` and skip `segment:` prefixed names.

### Types

| File | Key Types |
| ------ | ----------- |
| `types/schedule.ts` | `TimelineSegment` (id, execution_path, model_path, from, to, label), `StructureNode` (type, execution_path, label, children), `ScheduleData`, `ReifiedSchedule` |
| `types/simulation.ts` | `TimeseriesData` = `Record<species, Record<path, [t,v][]>>`, `TimeseriesMetadata`, `SimulationResult` (unified; `current_time`, `max_time`, `status` includes `'paused'`), `SimulationStatus`, `getProgress()`, `getMaxTime()`, `formatResultLabel()` |
| `types/network.ts` | `Node`, `Link`, `Network`, `UnionNetwork`, `ModelExclusions`, `linkId()`, `MODEL_NODE_KINDS` |

### Components

| File | Purpose |
| ------ | --------- |
| `App.vue` | 3-panel splitter layout |
| `TrackViewer.vue` | Toolbar (run/load/gene filter/track settings) + MainChart + fullscreen |
| `NetworkDiagram.vue` | Cytoscape graph via `NetworkView`. Model label overlay (bottom-left). Watches `scheduleStore.unionNetwork`. |
| `ScheduleEditor.vue` | Schedule dropdown + Monaco JSON editor + validation |

### Utils and Services

| File | Purpose |
| ------ | --------- |
| `utils/colorUtils.ts` | `parseHex`, `rgbToHex`, `lerpColor`, `lighten`, `darken`, `withOpacity` |
| `utils/api.ts` | `apiFetch`, `apiFetchJson`, `apiFetchText` with retry/timeout |
| `services/scheduleService.ts` | Schedule API: load, save, list, `fetchUnionNetwork`, `fetchNetwork`, `fetchNetworkFromSpec` |
| `services/simulationService.ts` | Simulation API: `runSimulation`, `loadResult`, `listResults`, `fetchTimeseriesForSpecies` |

### Composables

| File | Purpose |
| ------ | --------- |
| `composables/useSimulationStream.ts` | WebSocket connection for live simulation streaming. Singleton via `getSimulationStream()`. Functions: `connect`, `disconnect`, `subscribe(species)`, `pause`, `resume`, `track(id, callbacks)`, `untrack`. Callbacks: `ProgressCallback`, `TimeseriesCallback`, `StatusCallback`. Auto-reconnect on disconnect. |
