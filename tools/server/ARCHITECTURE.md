# Server Architecture

## Backend (Julia)

| File | Purpose | Key Exports |
| ------ | --------- | ------------- |
| `src/server.jl` | HTTP route definitions (Oxygen.jl) | Routes: schedules CRUD, `/schedules/{source}/{name}/network`, `POST /schedules/network`, simulation run/results |
| `src/schedule_visualisation.jl` | Schedule reification, network extraction, structure tree | Types: `Network`, `TimelineSegment`, `StructureNode`, `ScheduleData`, `ReifiedSchedule`, `ValidationMessage`. Functions: `reify_schedule`, `extract_network_for_model_path` |
| `src/schedule_storage.jl` | Schedule file persistence (examples/user/snapshot) | `list_schedules`, `load_schedule`, `save_schedule` |
| `src/simulation.jl` | Simulation execution and result management | `run_simulation`, `load_result`, `list_results` |
| `src/streaming_sink.jl` | Arrow IPC streaming for simulation events | `StreamingSink` |

## Frontend (Vue 3 + Pinia + SciChart)

### Stores

| File | Purpose | Key State/Actions |
| ------ | --------- | ------------------- |
| `scheduleStore.ts` | Schedule data, network cache | State: `schedule`, `networks`, `isLoading`. Computed: `allGenes`, `geneColours`, `segments`, `activeNetwork` (from viewerStore.activeModelPath). Actions: `loadScheduleByKey`, `loadScheduleBySpec`, `fetchNetwork` |
| `viewerStore.ts` | All selection/interaction state | State: `currentTimepoint`, `selectedGenes`, `selectedSpeciesTypes`, `selectedSegmentIds`, `activeModelPath`. Computed: `selectedPaths`. Actions: `selectSegments`, `setActiveModelPath` |
| `simulationStore.ts` | Simulation results | State: `currentResult`, `isSimulationRunning`. Computed: `timeseries`. Actions: `runSimulation`, `loadResult`, `getTimeseries(genes?, paths?)` |

### Charts

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

### Data Flow

1. Schedule loaded -> `scheduleStore.loadScheduleByKey/Spec` -> server returns `ScheduleData` (segments, structure, gene_colours, species_gene_mapping, no network)
2. `TrackViewer` watches schedule data -> `MainChart.setScheduleData` -> `TimelinePanel` computes layout rectangles -> `collectPathYRanges` passed to `PromoterPanel`. Then re-pushes simulation data via `refreshSimulationData()` so species mappings are fresh.
3. Simulation loaded -> `simulationStore.loadResult/runSimulation` -> timeseries watcher -> `refreshSimulationData()` (only if metadata ready) -> `MainChart.setSimulationData` -> filters by species type per panel
4. Gene selection: click on series -> `SelectSyncModifier` fires callback -> TrackViewer saves previous selection locally and sets `viewerStore.selectedGenes = [geneId]` -> watcher re-filters timeseries. Empty selection restores previous. ESC also restores.
5. Hover: `onHoveredChanged` on each series -> `SeriesSyncCoordinator.syncHover()` -> propagates `isHovered` to matching series + dims non-matching (opacity=0.3), skips null-group segments, invalidates parent surfaces for re-render
6. Segment click: `TimelinePanel` fires callback -> `viewerStore.selectSegments` + `scheduleStore.fetchNetwork(modelPath)` -> `activeNetwork` updates -> `NetworkDiagram` re-renders
7. Network loaded on-demand: `scheduleStore.fetchNetwork(modelPath)` -> cached in `networks` Map -> `activeNetwork` computed from `viewerStore.activeModelPath`. First model auto-loaded on schedule load.

### Key Naming Convention

`dataSeriesName` format: `{geneId}:{executionPath}` for timeseries, `segment:{segmentId}` for timeline rectangles. Sync modifiers extract gene ID as prefix before `:` and skip `segment:` prefixed names.

### Types

| File | Key Types |
| ------ | ----------- |
| `types/schedule.ts` | `TimelineSegment` (id, execution_path, model_path, from, to, label), `StructureNode` (type, execution_path, label, children), `ScheduleData`, `ReifiedSchedule` |
| `types/simulation.ts` | `TimeseriesData` = `Record<species, Record<path, [t,v][]>>`, `TimeseriesMetadata`, `SimulationResult` |
| `types/network.ts` | `Node`, `Link`, `Network` |

### Components

| File | Purpose |
| ------ | --------- |
| `App.vue` | 3-panel splitter layout |
| `TrackViewer.vue` | Toolbar (run/load/gene filter/track settings) + MainChart + fullscreen |
| `NetworkDiagram.vue` | Cytoscape graph, watches `scheduleStore.activeNetwork` |
| `ScheduleEditor.vue` | Schedule dropdown + Monaco JSON editor + validation |

### Utils and Services

| File | Purpose |
| ------ | --------- |
| `utils/colorUtils.ts` | `parseHex`, `rgbToHex`, `lerpColor`, `lighten`, `darken`, `withOpacity` |
| `utils/api.ts` | `apiFetch`, `apiFetchJson`, `apiFetchText` with retry/timeout |
| `services/scheduleService.ts` | Schedule API: load, save, list, `fetchNetwork`, `fetchNetworkFromSpec` |
| `services/simulationService.ts` | Simulation API: run, load result, list results |
