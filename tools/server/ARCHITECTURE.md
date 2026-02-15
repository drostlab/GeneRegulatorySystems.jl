# Server Architecture

## Backend (Julia)

| File | Purpose | Key Exports |
| ------ | --------- | ------------- |
| `src/server.jl` | HTTP route definitions (Oxygen.jl) | Routes: schedules CRUD, `POST /schedules/union-network`, `POST /schedules/network`, simulation run/results |
| `src/schedule_visualisation.jl` | Schedule reification, network extraction, structure tree | Types: `Network`, `UnionNetwork`, `ModelExclusions`, `TimelineSegment`, `StructureNode`, `ScheduleData`, `ReifiedSchedule`, `ValidationMessage`. Functions: `reify_schedule`, `extract_network_for_model_path`, `extract_union_network` |
| `src/schedule_storage.jl` | Schedule file persistence (examples/user/snapshot) | `list_schedules`, `load_schedule`, `save_schedule` |
| `src/simulation.jl` | Simulation execution and result management | `run_simulation`, `load_result`, `list_results` |
| `src/streaming_sink.jl` | Arrow IPC streaming for simulation events | `StreamingSink` |

## Frontend (Vue 3 + Pinia + SciChart + Cytoscape)

### Stores

| File | Purpose | Key State/Actions |
| ------ | --------- | ------------------- |
| `scheduleStore.ts` | Schedule data, union network | State: `schedule`, `unionNetwork`, `isLoading`. Computed: `allGenes`, `geneColours`, `segments`, `modelPaths`. Actions: `loadScheduleByKey`, `loadScheduleBySpec`, `fetchUnionNetwork` |
| `viewerStore.ts` | All selection/interaction state | State: `currentTimepoint`, `selectedGenes`, `selectedSpeciesTypes`, `selectedSegmentIds`, `activeModelPath`. Computed: `selectedPaths`, `proteinCountsAtTimepoint`, `maxProteinCounts`. Actions: `selectSegments`, `setActiveModelPath` |
| `simulationStore.ts` | Simulation results | State: `currentResult`, `isSimulationRunning`. Computed: `timeseries`. Actions: `runSimulation`, `loadResult`, `getTimeseries(genes?, paths?)` |

### Charts (SciChart)

| File | Purpose |
| ------ | --------- |
| `MainChart.ts` | Orchestrates all panels. Creates `SeriesSyncCoordinator` with gene grouping function and passes it to panels via `BasePanelOptions`. Callbacks: `onTimepointChange`, `onSelectionChange`, `onSegmentClick`. |
| `SeriesSyncCoordinator.ts` | Syncs hover state across subcharts by group key. Dims non-hovered series (opacity=0.3), skips null-group (segments). Invalidates parent surface after sync. Reentrancy-guarded. |
| `panels/BasePanel.ts` | Abstract base: surface, wasmContext, coordinator, visibility, `setTimeExtent` |
| `panels/TimeseriesPanel.ts` | Abstract: adds `metadata`, abstract `setData`, `clearData` |
| `panels/TimelinePanel.ts` | FastRectangleRenderableSeries for schedule segments. Path-only labels (small font). Hover tooltip shows label+path+model. Instant labels stacked at top. Click fires segment callback. |
| `panels/PromoterPanel.ts` | FastBandRenderableSeries for promoter activity, positioned by `pathYRanges`. Hover dims via coordinator. |
| `panels/CountsPanel.ts` | FastLineRenderableSeries for mRNA/protein counts. Hover dims via coordinator. RolloverModifier tooltip shows gene/path/value. |
| `charts/chartConstants.ts` | Centralised font family, font sizes, axis thickness, and segment palette |
| `layout/rectangleLayout.ts` | `layoutRectangles(structure, segments, yMin, yMax)` and `collectPathYRanges` |
| `modifiers/AxisSyncModifier.ts` | Syncs X-axis visible range across sub-charts |
| `modifiers/SelectSyncModifier.ts` | Syncs selection by group key across sub-charts. Accepts generic `GroupingFn`. Scans subcharts directly (no cache). |
| `modifiers/SharedTimeCursorModifier.ts` | Vertical cursor line synced across sub-charts |
| `modifiers/SubChartLayoutModifier.ts` | Vertical stacking of visible sub-charts |

### Network (Cytoscape)

| File | Purpose |
| ------ | --------- |
| `network/NetworkView.ts` | Orchestrator. Owns Cytoscape instance, lifecycle. Creates and coordinates sub-modules: `AdaptiveZoom`, `ModelFilter`, `SelectionSync`, `DynamicsSync`. `init(containerRef)` + `setNetwork(unionNetwork, geneColours)`. |
| `network/networkElements.ts` | `convertToElements(union, geneColours, geneOnly)` pure function. Filters model container nodes. `getDetailElements()` for species/reaction nodes added on zoom. |
| `network/networkStyles.ts` | `buildStylesheet(speciesVisible)` returns Cytoscape style array. Gene=round-rectangle, species=ellipse, reaction=tiny dot, orphan-species=70% gene size. Edge colours, dim/highlight classes. |
| `network/AdaptiveZoom.ts` | Single zoom threshold. Below: genes only. Above: adds species+reaction nodes via `cy.add()` with secondary fcose layout (gene positions pinned). Fires `onDetailChange` callback. |
| `network/ModelFilter.ts` | Watches `viewerStore.activeModelPath`. Hides nodes/edges not in the active model via `cy.remove()` + stash. Restores stashed on model switch. No re-layout needed (union positions stable). |
| `network/SelectionSync.ts` | Two-way sync: `viewerStore.selectedGenes` <-> Cytoscape node tap. Highlights selected gene nodes, dims others (opacity). Reentrancy-guarded. |
| `network/DynamicsSync.ts` | Watches `viewerStore.proteinCountsAtTimepoint`. Scales gene node width/height proportionally within min/max range. Debounced at 16ms. |

### Data Flow

1. Schedule loaded -> `scheduleStore.loadScheduleByKey/Spec` -> server returns `ScheduleData` (segments, structure, gene_colours, species_gene_mapping, no network)
2. `TrackViewer` watches schedule data -> `MainChart.setScheduleData` -> `TimelinePanel` computes layout rectangles -> `collectPathYRanges` passed to `PromoterPanel`. Then calls `scheduleStore.fetchUnionNetwork()` which eagerly fetches union of all models.
3. `NetworkDiagram` watches `scheduleStore.unionNetwork` -> `NetworkView.setNetwork()` -> renders gene-level graph -> fcose layout runs once -> sub-modules attach: `ModelFilter` hides excluded nodes for first model, `SelectionSync` + `DynamicsSync` start watching.
4. Simulation loaded -> `simulationStore.loadResult/runSimulation` -> timeseries watcher -> `refreshSimulationData()` -> `MainChart.setSimulationData` -> `viewerStore.proteinCountsAtTimepoint` updates -> `DynamicsSync` rescales gene nodes.
5. Gene selection: click on series (chart) -> `viewerStore.selectedGenes` updates -> `SelectionSync` highlights matching genes in network. Click on gene node (network) -> `viewerStore.selectedGenes` updates -> chart re-filters timeseries.
6. Segment click: `TimelinePanel` fires callback -> `viewerStore.setActiveModelPath` -> `ModelFilter` shows/hides elements for new model (no re-layout).
7. Zoom in past threshold -> `AdaptiveZoom` adds species/reaction nodes with secondary layout (gene positions pinned) -> `ModelFilter.refresh()` + `SelectionSync.refresh()`.

### Key Naming Convention

`dataSeriesName` format: `{geneId}:{executionPath}` for timeseries, `segment:{segmentId}` for timeline rectangles. Sync modifiers extract gene ID as prefix before `:` and skip `segment:` prefixed names.

### Types

| File | Key Types |
| ------ | ----------- |
| `types/schedule.ts` | `TimelineSegment` (id, execution_path, model_path, from, to, label), `StructureNode` (type, execution_path, label, children), `ScheduleData`, `ReifiedSchedule` |
| `types/simulation.ts` | `TimeseriesData` = `Record<species, Record<path, [t,v][]>>`, `TimeseriesMetadata`, `SimulationResult` |
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
| `services/simulationService.ts` | Simulation API: run, load result, list results |
