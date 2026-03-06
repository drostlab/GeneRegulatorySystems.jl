# Server Architecture

## Backend (Julia)

| File | Purpose | Key Exports |
| ------ | --------- | ------------- |
| `src/server.jl` | HTTP route definitions (Oxygen.jl) | Routes: schedules CRUD, `POST /schedules/union-network`, `POST /schedules/network`, `POST /simulations/{id}/timeseries` (filtered), `GET /simulations/{id}/phasespace` (returns stored phase-space result or 404), simulation run/results. After `run_simulation` completes, spawns a `Threads.@spawn` task that calls `PhaseSpace.compute_and_store`; on success sends `{ type: "phasespace_ready", simulation_id }` over WS. |
| `src/schedule_visualisation.jl` | Schedule reification, network extraction, structure tree | Types: `Network`, `UnionNetwork`, `ModelExclusions`, `TimelineSegment`, `StructureNode`, `ScheduleData`, `ReifiedSchedule`, `ValidationMessage`. Functions: `reify_schedule`, `extract_network_for_model_path`, `extract_union_network`, `gene_colours_from_spec` (public — dry-runs the schedule and returns `Dict{String,String}` gene→hex colour, used by the dim-reduction pipeline). Internal: `model_path_to_json_path`, `_gene_names`, `_spec_bindings`/`_spec_seed`, `_validate_spec`, `_label`/`_type_label`, `_collect_segments`. Gene colour system: `_gene_colours` (dispatch on model definition type — `RandomDifferentiation.Definition` → tree hues for core + grays for peripheral via `_diff_colours`; `Differentiation.Definition` → same; `KroneckerNetworks.Definition` → `_gray_colours`; `V1.Definition` → `_generate_gene_colours`). Tree hue helpers: `_collect_diff_leaves_node!`, `_assign_diff_hues!`/`_assign_diff_hues_node!`, `_diff_colours`. |
| `src/schedule_storage.jl` | Schedule file persistence (examples/user/snapshot) | `list_schedules`, `load_schedule`, `save_schedule` |
| `src/simulation.jl` | Simulation execution and result management | `run_simulation`, `load_result`, `list_results`, `load_timeseries_for_species` |
| `src/simulation_controller.jl` | Live simulation lifecycle (pause/resume, WS streaming, gene subscriptions) | `SimulationController`, `check_pause!`, `pause!`, `resume!`, `subscribe_genes!`, `send_progress`, `send_timeseries`, `send_status` |
| `src/streaming_sink.jl` | Arrow IPC storage + WS streaming during execution | `StreamingSimulationSink`, `flush!` |
| `src/phasespace.jl` | Post-simulation adaptive phase-space projection over protein species | Types: `PhaseSpacePoint` (x,y,path,t,colour), `PhaseSpaceResult` (adds `method`, `axis_labels`, `axis_top_genes`). Functions: `compute_and_store(result_path, simulation_id, gene_colours)`, `load_phasespace(result_path)`. Method selection: `_choose_method(n_genes)` → `:direct` (≤2 genes, highest-variance axes), `:pca` (≤20 genes, 2 leading PCs with variance-explained labels and top-loading gene), `:pca_umap` (>20 genes, PCA 50 → UMAP 2-D). Colouring: `_compute_colours` dispatches to `_softmax_colours` when saturated gene colours present (differentiation), or `_path_colours` (evenly-spaced hues by execution path) otherwise. Internal helpers: `_load_protein_timeseries`, `_collect_cells`, `_step_value`, `_build_expression_matrix`, `_run_direct`, `_run_pca_2d`, `_run_pca_umap`, `_coloured_gene_indices`, `_is_saturated`, `_to_hex`, `_store`. |

## Frontend (Vue 3 + Pinia + SciChart + Cytoscape)

### Stores

| File | Purpose | Key State/Actions |
| ------ | --------- | ------------------- |
| `scheduleStore.ts` | Schedule data, union network | State: `schedule`, `unionNetwork`, `isLoading`, `isNetworkLoading`. Computed: `allGenes`, `geneColours`, `segments`, `modelPaths`. Actions: `loadScheduleByKey`, `loadScheduleBySpec`, `fetchUnionNetwork`, `clearNetwork`. Spec-skip: compares new spec to current before reloading. |
| `viewerStore.ts` | All selection/interaction state | State: `currentTimepoint`, `selectedGenes`, `selectedSpeciesNodes`, `selectedSpeciesTypes`, `selectedSegmentIds`, `hoveredModelPath`, `hoveredExecutionPath` (exposed), `hoveredGeneId` (exposed). Computed: `activeModelPath` (hovered model takes priority, else derived from currentTimepoint + segments), `selectedPaths`, `proteinCountsAtTimepoint` (filters to hovered path or active-at-timepoint paths), `maxProteinCounts`. Actions: `selectSegments`, `selectExecutionPath(path)`, `setHoveredRectModel`, `setHoveredInstantModel`, `setHoveredGene(gene)` |
| `simulationStore.ts` | Simulation results with lazy loading + streaming | State: `currentResult` (`SimulationResult | null`), `isSimulationRunning`, `isPaused`, `timeseriesCache`, `fetchedGenes`, `streamingBuffer`, `phaseSpaceResult` (`PhaseSpaceResult | null`), `isPhaseSpacePending`. Computed: `timeseries`, `progress`, `currentResultId`, `currentResultLabel`, `isPhaseSpaceAvailable`. Actions: `runSimulation`, `loadResult`, `fetchGeneTimeseries(genes)`, `getTimeseries(genes?, paths?)`, `pauseSimulation`, `resumeSimulation`, `updateStreamSubscription(genes)`. Phase-space wiring: on status=completed, registers `trackPhaseSpace(simId, _onPhaseSpaceReady)` before `untrack()`; `_onPhaseSpaceReady` fetches HTTP and sets `phaseSpaceResult`. `loadResult` also eagerly tries `fetchPhaseSpace` (best-effort). |

### Charts (SciChart)

| File | Purpose |
| ------ | --------- |
| `MainChart.ts` | Orchestrates all panels. Manages two `PanelGroup`s (`timeseriesGroup`, `phaseSpaceGroup`) and a `ChartLayout` tree. Scoped modifiers only operate on `timeseriesGroup`. Phase-space API: `showPhaseSpace(result)`, `hidePhaseSpace()`, `setPhaseSpaceData(result)`, `setPhaseSpaceTimepoint(t)`, `onPhaseSpacePathSelect(cb)`, `onPhaseSpaceHover(cb)`. Highlight: `highlightPath(path)` and `highlightGene(gene)` fan out to all panels (composable -- both filters apply simultaneously). Callbacks: `onTimepointChange`, `onSelectionChange`, `onSegmentClick`, `onHoverChange`, `onTimeseriesPathHover(cb)`. |
| `panels/BasePanel.ts` | Abstract base: SciChartSubSurface, wasmContext, visibility, `setTimeExtent`. Composable highlight system: `highlightPath(path)` + `highlightGene(gene)` set independent filters, both call `_applyHighlightFilters()`. Helper `_seriesMatchesFilters(name)` checks `<gene>:<path>` naming against both active filters. Exported utilities: `extractGene(name)`, `extractPath(name)`, `PATH_DIM_OPACITY`. Methods: `applyTheme`, `dispose`. |
| `panels/TimeseriesPanel.ts` | Abstract: adds `metadata`, `pathTimeRanges`, segment boundary dashed lines (`setSegmentBoundaries`), `onPathHover(cb)` (wired to `TimeseriesHoverModifier`), abstract `setData`, `appendStreamingData`, `clearData` |
| `panels/TimelinePanel.ts` | FastRectangleRenderableSeries for schedule segments. Dynamic label sizing. Click-to-select zooms x-axis. Hover fires `onHoverChange`. Overrides `highlightPath` to dim segments by execution path (maps `segment:<id>` → `LayoutRectangle.executionPath`). Hover transition guard: `currentHoveredExecution` prevents stale unhover from clearing a newly-hovered rectangle. |
| `panels/PromoterPanel.ts` | FastBandRenderableSeries for promoter activity, positioned by `pathYRanges`. Streaming with cursor extension. |
| `panels/CountsPanel.ts` | FastLineRenderableSeries for mRNA/protein counts. Streaming with cursor extension. SweepAnimation on `setData`. |
| `panels/PhaseSpacePanel.ts` | BasePanel subclass for phase-space embedding. Per-path trajectory lines + scatter points + hollow-circle timepoint highlight (theme-aware stroke). Methods: `setPhaseSpaceData(result)`, `setTimepoint(t)`, `onPathSelect(cb)`, `onHover(cb)`. Overrides `highlightPath` to skip when `PhaseSpaceHoverModifier` is active (avoids circular dimming). Hover/dimming/tooltip delegated to `PhaseSpaceHoverModifier`. Own zoom/pan modifiers (independent of timeseries). |
| `charts/chartConstants.ts` | Centralised font family, font sizes, axis thickness, segment palette. |
| `charts/theme.ts` | `getSciChartTheme(isDark)` -- bridge to `getTheme(isDark).sciChartTheme` |
| `layout/PanelGroup.ts` | Lightweight registry of related panels. `add(id, panel)`, `remove(id)`, `visibleSurfaces`, `allSurfaces`. Used by scoped modifiers and ChartLayout. |
| `layout/ChartLayout.ts` | Recursive tree-based layout engine replacing SubChartLayoutModifier. `LayoutNode` = `GroupNode` (vertical stack of a PanelGroup) or `SplitNode` (horizontal/vertical split with ratio). Manages `SciChartVerticalGroup` per PanelGroup. Adaptive y-axis font scaling. |
| `layout/rectangleLayout.ts` | `layoutRectangles(structure, segments, yMin, yMax)` and `collectPathYRanges`. Caps at `MAX_TIMELINE_PATHS=10` duration paths; excess paths are excluded from layout. |
| `modifiers/AxisSyncModifier.ts` | Scoped to a `PanelGroup`. Syncs X-axis visible range only across group's surfaces. |
| `modifiers/DragGuardModifier.ts` | Tracks mouse delta between mouseDown/mouseMove. Exposes `isDrag` flag for click-vs-drag discrimination. |
| `modifiers/SelectSyncModifier.ts` | Scoped to a `PanelGroup`. Syncs selection by group key across group's surfaces. Accepts generic `GroupingFn`. |
| `modifiers/SharedTimeCursorModifier.ts` | Scoped to a `PanelGroup`. Vertical cursor line synced across group's surfaces. |
| `modifiers/TimeseriesHoverModifier.ts` | Custom `ChartModifierBase2D` for timeseries hover. Nearest-point hit-test with tooltip. Fires `onPathHover(path)` callback when the hovered execution path changes, enabling bidirectional path highlight sync. |
| `modifiers/PhaseSpaceHoverModifier.ts` | Custom `ChartModifierBase2D` for phase-space hover. Uses `hitTestProvider.hitTestDataPoint` on scatter series for accurate sub-surface hit-testing. Path dimming, tooltip DOM, hover callback. Exposes `isHovering` getter for external guard. |

### Network (Cytoscape)

| File | Purpose |
| ------ | --------- |
| `network/NetworkView.ts` | Orchestrator. Owns Cytoscape instance, lifecycle. Creates and coordinates sub-modules. Uses `layoutstop` event (not timeout). Layout: fcose with nodeRepulsion=50000, idealEdgeLength=100, edgeElasticity=0.8, numIter=5000. |
| `network/networkElements.ts` | `getGeneViewElements(network, geneColours)` — gene nodes + orphan species + scope `all`/`gene` edges (resolved to gene parents via `buildNodeParentMap`). `getSpeciesViewElements(network, geneColours)` — species/reaction compound children + scope `all`/`species` edges (actual endpoints). `buildNodeParentMap(network, geneNames)` — maps node names to gene parents for generic endpoint resolution. |
| `network/networkStyles.ts` | `buildStylesheet()` returns Cytoscape style array. `.excluded { display: none }` for ModelFilter. Compound parent selector `$node > node` for gene label positioning. Self-loop edge style. |
| `network/AdaptiveZoom.ts` | Zoom threshold (1.2). Precomputes gene-view and species-view element sets on `attach()`. Below threshold: gene nodes + gene-scope edges. Above: swaps in species/reaction nodes + species-scope edges. Species positioning: known types (mRNA/protein/active) cascade below gene, unknowns circular, reactions at neighbour centroid. 50ms debounce. Fires `onDetailChange` callback. |
| `network/ModelFilter.ts` | Watches `viewerStore.activeModelPath`. Toggles `.excluded` CSS class on nodes/edges (no add/remove, avoids conflicts with AdaptiveZoom). |
| `network/SelectionSync.ts` | Two-way sync: `viewerStore.selectedGenes` + `viewerStore.selectedSpeciesNodes` <-> Cytoscape node tap. Gene taps toggle `selectedGenes`; orphan-species taps toggle `selectedSpeciesNodes`. Local `visualSelection` (union of both) drives all dimming/highlighting uniformly via `resolveSelectable` — no node-type special-cases. Highlights selected genes, dims everything else. Edges undimmed when either endpoint is in `visualSelection`. |
| `network/HoverSync.ts` | Bidirectional gene hover sync. Network -> Store: `mouseover`/`mouseout` on `node.gene` sets `viewerStore.hoveredGeneId`. Store -> Network: watches `hoveredGeneId` and toggles `.gene-hover` CSS class (border highlight) on the corresponding Cytoscape node. `fromCy` guard prevents circular events. |
| `network/DynamicsSync.ts` | Watches `viewerStore.proteinCountsAtTimepoint` + `selectedGenes`. Only resizes selected genes; unselected stay at base size. Debounced at 16ms. Scales `padding` (6-40px) on gene nodes in both gene and species view — works for both leaf and compound-parent nodes. `notifyDetailChanged()` called by `NetworkView` on view transitions to reapply sizing immediately. |
| `network/Tooltip.ts` | Unified parameterised tooltip. `Tooltip` class: selector, content function, tooltip ID. Factories: `createEdgeTooltip()` (shows link kind on edge hover), `createNodeTooltip()` (shows node name/kind on node hover). Lightweight DOM element positioned at cursor. |

### Theming & Dark Mode

| File | Purpose |
| ------ | --------- |
| `config/theme.ts` | Single source of truth. Palettes (RED, PURPLE, GREEN, GREY), EDGE_COLOURS (mode-independent; includes `produces` for summary production edges), light/dark ThemeMode objects, `getTheme(isDark)`, `palette` export for PrimeVue preset. Each ThemeMode bundles a SciChart `IThemeProvider`. |
| `composables/useTheme.ts` | Reactive `isDark` ref, OS-preference fallback, localStorage persistence. `toggle()`, `onThemeChange(fn)` for imperative consumers. Toggles `.app-dark` class on `<html>`. |
| `utils/logging.ts` | Lightweight tagged logger: `getLogger(tag)` returns `{ debug, info, warn, error }`. Debug only in dev. |

**Architecture:** `theme.ts` defines hex palettes once. Mode themes reference only palette entries. PrimeVue reads `palette.*` in `main.ts` preset. SciChart/Cytoscape call `getTheme(isDark)`. `useTheme` composable provides reactive state; Vue components wire `onThemeChange` to call `MainChart.applyTheme(dark)` / `NetworkView.applyTheme(dark)` for runtime switching.

### Data Flow

1. Schedule loaded -> `scheduleStore.loadScheduleByKey/Spec` -> server returns `ScheduleData` (segments, structure, genes, gene_colours, no network)
2. `TrackViewer` watches schedule data -> `MainChart.setScheduleData` -> `TimelinePanel` computes layout rectangles -> `collectPathYRanges` passed to `PromoterPanel`. Then calls `scheduleStore.fetchUnionNetwork()` which eagerly fetches union of all models.
3. `NetworkDiagram` watches `scheduleStore.unionNetwork` -> `NetworkView.setNetwork()` -> renders gene-level graph (gene nodes + orphan species + resolved edges) -> fcose layout runs once -> sub-modules attach: `AdaptiveZoom` precomputes both view element sets, `ModelFilter` hides excluded nodes for first model, `SelectionSync` + `DynamicsSync` start watching.
4. Simulation loaded -> `simulationStore.loadResult` loads metadata only. `selectedGenes` watcher triggers `fetchGeneTimeseries(genes)` which lazily loads per-gene timeseries via `POST /simulations/{id}/timeseries`. After fetch -> `refreshSimulationData()` pushes to chart with `SweepAnimation`.
5. Gene selection: click on series (chart) -> `viewerStore.selectedGenes` updates -> lazy fetch for new genes -> `SelectionSync` highlights in network. Click on gene node (network) -> same flow.
6. `activeModelPath` is a computed that prioritises `hoveredModelPath` (from timeline hover), falling back to `currentTimepoint` + segments. Hovering a timeline segment updates the network in real-time.
7. **Path highlight sync:** `viewerStore.hoveredExecutionPath` is the single hub. Writers: `TimelinePanel` hover, `PhaseSpaceHoverModifier`, `TimeseriesHoverModifier` (all via `setHoveredRectModel`). Reader: one watcher in `TrackViewer` calls `MainChart.highlightPath(path)` which fans out `BasePanel.highlightPath()` to every panel. `TimelinePanel` overrides to map `segment:<id>` to execution paths. `PhaseSpacePanel` overrides to skip when its own modifier is active. `PromoterPanel` overrides to rewrite `fillY1` alpha (band opacity doesn't affect fill). `PATH_DIM_OPACITY` exported from `BasePanel`.
8. **Gene highlight sync (bidirectional):** `viewerStore.hoveredGeneId` is the hub. Writers: `HoverSync` (network gene node hover) and `TimeseriesHoverModifier` (timeseries panel hover, via `onGeneHover` callback -> `TrackViewer` -> store). Readers: (a) watcher in `TrackViewer` calls `MainChart.highlightGene(gene)` which fans out to all panels; (b) `HoverSync` watches the store and toggles `.gene-hover` on the Cytoscape node. Composable with path highlight: `BasePanel._seriesMatchesFilters()` checks both gene and path filters on `<gene>:<path>` series names. `PhaseSpacePanel` and `TimelinePanel` override `highlightGene` as no-ops.
9. Zoom in past threshold -> `AdaptiveZoom` swaps gene-scope edges for species-scope edges and adds species/reaction compound children (gene positions pinned) -> `ModelFilter.refresh()` + `SelectionSync.refresh()`.

### Simulation Streaming

**Backend flow:**
1. `POST /simulations/run` creates a `SimulationController` and stores it as `active_controller`. Returns immediately with `status=running`.
2. `StreamingSimulationSink` receives every simulation event. It writes Arrow IPC to disk, and if the controller has subscribed species, accumulates timeseries data per species/path.
3. At time-window intervals (`stream_interval = 1000.0` sim-time units), the sink sends a `progress` message and a `timeseries` batch to the WS client via the controller.
4. When the simulation completes, the sink sends a final `status: completed` message.

**WS protocol** (`/ws`):
- Client -> Server: `{ type: "subscribe", species: [...] }`, `{ type: "pause" }`, `{ type: "resume" }`
- Server -> Client: `{ type: "progress", simulation_id, current_time, frame_count }`, `{ type: "timeseries", simulation_id, data: TimeseriesData }`, `{ type: "status", simulation_id, status, error? }`, `{ type: "phasespace_ready", simulation_id }` (sent after phase-space computation completes; client then fetches `GET /simulations/{id}/phasespace`)

**Pause/resume:** `check_pause!(controller)` is called on every sink event. When paused, the simulation thread blocks on a `Threads.Condition`. Resume notifies the condition.

**Frontend flow:**
1. `simulationStore.runSimulation()` connects the WS via `useSimulationStream`, tracks the simulation ID, and subscribes the first N selected genes.
2. WS `progress` callbacks update `currentResult.current_time`; `streamingDelta` holds the latest timeseries batch (not cumulative).
3. `TrackViewer.vue` watches `streamingDelta` with RAF throttle, calling `MainChart.appendStreamingData(data, currentTime)` which routes to `CountsPanel` / `PromoterPanel`. During streaming, the timeseries cache watcher is skipped (`isSimulationRunning` guard) to prevent `setData` from overwriting incremental appends.
4. Each panel maintains a `seriesMap` of persistent `XyDataSeries` / `XyyDataSeries` and a **trailing cursor extension point**: a temporary last point at `min(currentTime, pathEndTime)` with the last known value. Cursor points are clamped to the path's time range via `pathTimeRanges` (computed from segments by `getPathTimeRanges`) so they don't extend into later segments.
5. `PromoterPanel` pre-computes band layout params (yCenter, bandHeight) for every (gene, path) key when `setPathYRanges` or `setMetadata` is called, so streaming doesn't need to guess band dimensions.
6. Progress-driven time cursor sync moves `viewerStore.currentTimepoint` during simulation.
7. On completion, the store clears the streaming cache and refetches definitive timeseries via HTTP. `setData` renders the complete result with `SweepAnimation`.
8. Before calling `untrack()` on status=completed, the store registers `trackPhaseSpace(simId, _onPhaseSpaceReady)`. When the server sends `phasespace_ready`, `_onPhaseSpaceReady` fetches `GET /simulations/{id}/phasespace` and sets `phaseSpaceResult`. `TrackViewer` auto-shows `PhaseSpacePanel` when `isPhaseSpaceAvailable` flips to true. `PhaseSpacePanel` also tries to load a pre-existing phase-space result when `loadResult` is called for an already-completed simulation.

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
| `types/schedule.ts` | `TimelineSegment` (id, execution_path, model_path, json_path, from, to, label), `StructureNode` (type, execution_path, label, children), `ScheduleData`, `ReifiedSchedule`. Functions: `getPathTimeRanges`, `getSegmentBoundaryTimes`, `getActivePathsAtTime` |
| `types/simulation.ts` | `TimeseriesData` = `Record<species, Record<path, [t,v][]>>`, `TimeseriesMetadata`, `SimulationResult` (unified; `current_time`, `max_time`, `status` includes `'paused'`), `SimulationStatus`, `PhaseSpacePoint` (x, y, path, t, colour), `PhaseSpaceResult` (simulation_id, method, axis_labels, axis_top_genes, points, n_genes, n_cells), `getProgress()`, `getMaxTime()`, `formatResultLabel()` |
| `types/network.ts` | `Node`, `Link` (with `scope: LinkScope`), `LinkScope` (`'all' | 'gene' | 'species'`), `Network`, `UnionNetwork`, `ModelExclusions`, `linkId()`, `MODEL_NODE_KINDS` |

### Components

| File | Purpose |
| ------ | --------- |
| `App.vue` | 3-panel splitter layout |
| `TrackViewer.vue` | Toolbar (run/load/gene filter/track settings/phase-space toggle) + MainChart. `showPhaseSpace` ref auto-set true when `isPhaseSpaceAvailable` becomes true; toggles `chart.showPhaseSpace(result)` / `chart.hidePhaseSpace()`. Watches phase-space result + timepoint. |
| `NetworkDiagram.vue` | Cytoscape graph via `NetworkView`. Model label overlay (bottom-left). Watches `scheduleStore.unionNetwork`. |
| `ScheduleEditor.vue` | Schedule dropdown + Monaco JSON editor + validation. Watches `viewerStore.hoveredModelPath` and `selectedSegmentIds`; resolves the corresponding `json_path` from loaded segments via `findRangeForJsonPath`, then calls `highlightScope`/`clearScopeHighlight` to highlight and optionally scroll to the active scope in the editor. |

### Utils and Services

| File | Purpose |
| ------ | --------- |
| `utils/colorUtils.ts` | `parseColour` (hex + HSL), `rgbToHex`, `lerpColor`, `lighten`, `darken`, `withOpacity` |
| `utils/jsonPathUtils.ts` | `findRangeForJsonPath(text, path)` — resolves a `(string|number)[]` JSONPath (as produced by the backend's `model_path_to_json_path`) to `{ startOffset, endOffset }` inside a JSON string using `jsonc-parser` |
| `utils/api.ts` | `apiFetch`, `apiFetchJson`, `apiFetchText` with retry/timeout |
| `services/scheduleService.ts` | Schedule API: load, save, list, `fetchUnionNetwork`, `fetchNetwork`, `fetchNetworkFromSpec` |
| `services/simulationService.ts` | Simulation API: `runSimulation`, `loadResult`, `listResults`, `fetchTimeseriesForSpecies`, `fetchPhaseSpace(resultId)` (GET `/simulations/{id}/phasespace`, returns `PhaseSpaceResult | null` on 404) |

### Composables

| File | Purpose |
| ------ | --------- |
| `composables/useSimulationStream.ts` | WebSocket connection for live simulation streaming. Singleton via `getSimulationStream()`. Functions: `connect`, `disconnect`, `subscribe(species)`, `pause`, `resume`, `track(id, callbacks)`, `untrack` (clears only progress/timeseries/status callbacks), `trackPhaseSpace(simId, cb)` (separate callback that survives `untrack()`), `clearPhaseSpaceTracking()`. Callbacks: `ProgressCallback`, `TimeseriesCallback`, `StatusCallback`, `PhaseSpaceReadyCallback`. Handles `phasespace_ready` WS message type. Auto-reconnect on disconnect. |
| `composables/useMonacoEditor.ts` | Monaco editor lifecycle: `init`, `setValue`, `getContent`, `updateOptions`, `dispose`. Scope highlighting: `highlightScope(startOffset, endOffset, scroll?)` adds a decoration (`scope-highlight` + `scope-highlight-gutter` CSS classes) and optionally scrolls; `clearScopeHighlight()` removes it. |
