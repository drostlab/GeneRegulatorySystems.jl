<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue'
import { useSimulationStore } from '@/stores/simulationStore'
import { useScheduleStore } from '@/stores/scheduleStore'
import { useViewerStore } from '@/stores/viewerStore'
import type { SimulationResult } from '@/types/simulation'
import { formatResultLabel } from '@/types/simulation'
import { speciesTypeLabels, DEFAULT_VISIBLE_SPECIES_TYPES, SPECIES_TYPES } from '@/types/schedule'
import type { SpeciesType } from '@/types/schedule'
import Button from 'primevue/button'
import Select, { type SelectChangeEvent } from 'primevue/select'
import MultiSelect from 'primevue/multiselect'
import InputText from 'primevue/inputtext'
import ProgressSpinner from 'primevue/progressspinner'
import ProgressBar from 'primevue/progressbar'
import OverlayPanel from 'primevue/overlaypanel'
import Checkbox from 'primevue/checkbox'
import * as simulationService from '@/services/simulationService'
import { MainChart } from '@/charts/MainChart'

const simulationStore = useSimulationStore()
const scheduleStore = useScheduleStore()
const viewerStore = useViewerStore()

const DEFAULT_SELECTED_GENES_COUNT = 5

const containerRef = ref<HTMLDivElement>()
const results = ref<SimulationResult[]>([])
const isFullscreen = ref<boolean>(false)
const selectedTracks = ref<string[]>([])
const trackSettingsPanel = ref()
const previousGeneSelection = ref<string[] | null>(null)

const chart = new MainChart()

const isScheduleLoading = computed(() => scheduleStore.isLoading)
const isSimulationBusy = computed(() => simulationStore.isSimulationRunning || simulationStore.isLoadingResult)

const isUiDisabled = computed(() => isScheduleLoading.value || isSimulationBusy.value)

/** Progress percentage for the progress bar (0-100). */
const progressPercent = computed(() => Math.round(simulationStore.progress * 100))

/** True when timeseries has never been loaded (first fetch needs a full overlay). */
const isFirstTimeseriesFetch = computed(() =>
    simulationStore.isFetchingTimeseries && simulationStore.fetchedGenes.size === 0
)

const trackOptions = computed(() => {
    const options: Array<{ label: string; value: string }> = []
    
    // Only include schedule if loaded
    if (scheduleStore.isLoaded) {
        options.push({ label: 'Schedule Timeline', value: 'schedule' })
    }
    
    // Only include species types if simulation loaded
    if (simulationStore.isLoaded) {
        SPECIES_TYPES.forEach(type => {
            options.push({ label: speciesTypeLabels[type], value: type })
        })
    }
    
    return options
})

watch(
    () => ({
        scheduleLoaded: scheduleStore.isLoaded,
        simulationLoaded: simulationStore.isLoaded
    }),
    (state, oldState) => {
        const validTracks: string[] = []
        
        if (state.scheduleLoaded) {
            validTracks.push('schedule')
        }
        
        if (state.simulationLoaded) {
            SPECIES_TYPES.forEach(type => validTracks.push(type))
        }

        // Set defaults when simulation transitions to loaded
        const simulationJustLoaded = state.simulationLoaded && !oldState?.simulationLoaded
        if (simulationJustLoaded) {
            const defaults: string[] = []
            if (state.scheduleLoaded) {
                defaults.push('schedule')
            }
            defaults.push(...DEFAULT_VISIBLE_SPECIES_TYPES)
            selectedTracks.value = defaults
            return
        }
        
        const filtered = selectedTracks.value.filter(t => validTracks.includes(t))
        
        if (filtered.length !== selectedTracks.value.length) {
            selectedTracks.value = filtered
            updateViewerStore()
        }
    }
)

watch(
    () => ({ structure: scheduleStore.schedule.data?.structure, segments: scheduleStore.segments, metadata: scheduleStore.timeseriesMetadata }),
    async ({ structure, segments, metadata }) => {
        if (structure && segments && segments.length > 0 && metadata) {
            // Stale-closure guard: ignore if schedule changed mid-flight
            const specAtStart = scheduleStore.schedule.spec
            console.debug(`[TrackViewer] Schedule data ready: ${segments.length} segments`)
            chart.setScheduleData(structure, segments, metadata)

            // Fire network fetch without blocking (chart already rendered)
            scheduleStore.fetchUnionNetwork().catch(e => {
                console.error('[TrackViewer] Failed to fetch union network:', e)
            })

            // Only refresh if schedule hasn't changed during the above
            if (scheduleStore.schedule.spec === specAtStart) {
                refreshSimulationData()
            }
        }
    }
)

watch(
    () => scheduleStore.allGenes,
    (allGenes) => {
        if (allGenes && allGenes.length > 0) {
            if (simulationStore.isLoaded) {
                viewerStore.selectedGenes = allGenes.slice(0, DEFAULT_SELECTED_GENES_COUNT)
            } else {
                // No simulation: select all genes so the network looks complete
                viewerStore.selectedGenes = [...allGenes]
            }
        }
    }
)

// Lazy-fetch timeseries when selected genes change (refresh handled by data watcher below)
watch(
    () => viewerStore.selectedGenes,
    async (genes) => {
        if (!simulationStore.isLoaded || genes.length === 0) return

        // During streaming, only update WS subscription (HTTP fetch deferred to completion)
        if (simulationStore.isSimulationRunning) {
            simulationStore.updateStreamSubscription(genes)
            return
        }

        await simulationStore.fetchGeneTimeseries(genes)
    },
    { deep: true }
)

/** Push current simulation data to chart, filtered by selected genes/paths. */
function refreshSimulationData(): void {
    const genes = viewerStore.selectedGenes
    const paths = viewerStore.selectedPaths
    const pathArray = paths ? [...paths] : null
    const visibleData = simulationStore.getTimeseries(genes, pathArray)
    if (visibleData) {
        chart.setSimulationData(visibleData)
    }
}

function updateViewerStore() {
    viewerStore.selectedSpeciesTypes = selectedTracks.value.filter(t => t !== 'schedule') as SpeciesType[]
}

async function loadResults() {
    results.value = await simulationService.fetchResultsList()
}


onMounted(async () => {
    loadResults()
    await chart.init(containerRef)
    chart.setVisibleTracks(['schedule'])

    chart.onTimepointChange((timepoint: number) => {
        viewerStore.setTimepoint(timepoint)
    })

    chart.onSelectionChange((selectedGenes: string[]) => {
        console.debug(`[TrackViewer] Selection callback: [${selectedGenes}], previous: [${viewerStore.selectedGenes}]`)
        if (selectedGenes.length === 1) {
            previousGeneSelection.value = [...viewerStore.selectedGenes]
            viewerStore.selectedGenes = [selectedGenes[0]!]
        } else if (selectedGenes.length === 0 && previousGeneSelection.value) {
            // Restore previous selection when user clicks empty space
            console.debug(`[TrackViewer] Restoring previous selection: [${previousGeneSelection.value}]`)
            viewerStore.selectedGenes = previousGeneSelection.value
            previousGeneSelection.value = null
        }
    })

    chart.onSegmentClick(async (segmentId: number, _modelPath: string) => {
        console.debug(`[TrackViewer] Segment click: id=${segmentId}`)
        viewerStore.selectSegments(new Set([segmentId]))
    })

    window.addEventListener('keydown', handleEscapeKey)
})

onBeforeUnmount(() => {
    chart.dispose()
    window.removeEventListener('keydown', handleEscapeKey)
})

async function loadResult(event: SelectChangeEvent) {
    const selectedResultId = event.value
    simulationStore.clearResult()
    chart.clearSimulationData()

    await simulationStore.loadResult(selectedResultId)

    // If schedule was same spec, watchers won't fire -- explicitly fetch timeseries
    const genes = viewerStore.selectedGenes
    if (genes.length > 0 && simulationStore.isLoaded) {
        await simulationStore.fetchGeneTimeseries(genes)
    }
}

async function runSimulation() {
    chart.clearSimulationData()
    // runSimulation returns immediately (async server-side), then WS streams data
    simulationStore.runSimulation().then(() => loadResults())
}

function pauseSimulation() {
    simulationStore.pauseSimulation()
}

function resumeSimulation() {
    simulationStore.resumeSimulation()
}

function clearSimulation() {
    chart.clear()
    simulationStore.clearResult()
    selectedTracks.value = scheduleStore.isLoaded ? ['schedule'] : []
}

function toggleFullscreen() {
    isFullscreen.value = !isFullscreen.value
}

function handleEscapeKey(event: KeyboardEvent) {
    if (event.key === 'Escape') {
        if (previousGeneSelection.value) {
            viewerStore.selectedGenes = previousGeneSelection.value
            previousGeneSelection.value = null
            return
        }
        if (isFullscreen.value) {
            isFullscreen.value = false
        }
    }
}

watch(
    () => selectedTracks.value,
    (newTracks) => {
        chart.setVisibleTracks(newTracks)
        updateViewerStore()
    }
)

// Single watcher for all simulation data refresh triggers
// Fires when timeseries cache, gene selection, or path selection changes
// Skips during running simulation (streaming delta watcher handles that)
watch(
    () => ({ timeseries: simulationStore.timeseries, genes: viewerStore.selectedGenes, paths: viewerStore.selectedPaths }),
    ({ timeseries }) => {
        if (simulationStore.isSimulationRunning) return
        if (timeseries && scheduleStore.timeseriesMetadata) {
            refreshSimulationData()
        } else if (!timeseries) {
            chart.clearSimulationData()
        }
    },
    { deep: true }
)

// During a running simulation, push streaming data to the chart via RAF throttle
let streamingRafId: number | null = null
let pendingStreamingData: Record<string, Record<string, Array<[number, number]>>> | null = null
let lastStreamCurrentTime = 0

watch(
    () => simulationStore.currentResult,
    (result) => {
        if (!result || !simulationStore.isSimulationRunning) return

        // Sync time cursor with simulation progress
        if (result.current_time > 0) {
            viewerStore.setTimepoint(result.current_time)
        }
    },
    { deep: true }
)

// Watch streaming delta during simulation to push incremental data to chart
watch(
    () => ({ delta: simulationStore.streamingDelta, running: simulationStore.isSimulationRunning, ct: simulationStore.currentResult?.current_time }),
    ({ delta, running, ct }) => {
        if (!running || !delta) return
        pendingStreamingData = delta
        lastStreamCurrentTime = ct ?? 0
        _scheduleStreamingFlush()
    },
    { deep: true }
)

function _scheduleStreamingFlush(): void {
    if (streamingRafId !== null) return
    streamingRafId = requestAnimationFrame(() => {
        streamingRafId = null
        if (pendingStreamingData && scheduleStore.timeseriesMetadata) {
            chart.appendStreamingData(pendingStreamingData, lastStreamCurrentTime)
            pendingStreamingData = null
        }
    })
}

</script>



<template>
    <Teleport to="body" :disabled="!isFullscreen">
        <div class="simulation-viewer" :class="{ 'fullscreen-mode': isFullscreen }">
        <div class="card-header">
            <div class="card-header-row">
                <div class="header-left">
                    <div class="results-control">
                        <Select
                            v-if="!simulationStore.isSimulationRunning"
                            :model-value="simulationStore.currentResultId"
                            :options="results"
                            :disabled="isScheduleLoading"
                            option-value="id"
                            size="small"
                            placeholder="Load simulation result..."
                            @change="loadResult"
                            class="dropdown-small"
                            append-to="body"
                        >
                            <template #option="slotProps">
                                <div class="dropdown-option">{{ formatResultLabel(slotProps.option) }}</div>
                            </template>
                            <template #value="slotProps">
                                <div v-if="slotProps.value" class="dropdown-option">
                                    {{ formatResultLabel(results.find(r => r.id === slotProps.value)!) }}
                                </div>
                                <span v-else class="dropdown-option">Load simulation result...</span>
                            </template>
                            <template #empty>
                                <div class="dropdown-option">No available results</div>
                            </template>
                        </Select>

                        <InputText
                            v-else
                            :model-value="simulationStore.currentResultLabel"
                            disabled
                            size="small"
                            class="input-small"
                        />
                    </div>

                    <Button
                        v-if="!simulationStore.isSimulationRunning"
                        label="Run Simulation"
                        icon="pi pi-play-circle"
                        :disabled="isUiDisabled"
                        size="small"
                        severity="success"
                        @click="runSimulation"
                        class="run-simulation-btn"
                    />

                    <Button
                        v-if="simulationStore.isSimulationRunning && !simulationStore.isPaused"
                        icon="pi pi-pause"
                        size="small"
                        severity="warn"
                        @click="pauseSimulation"
                        title="Pause simulation"
                    />
                    <Button
                        v-if="simulationStore.isSimulationRunning && simulationStore.isPaused"
                        icon="pi pi-play"
                        size="small"
                        severity="success"
                        @click="resumeSimulation"
                        title="Resume simulation"
                    />

                    <div v-if="simulationStore.isSimulationRunning" class="progress-wrapper">
                        <ProgressBar
                            :value="progressPercent"
                            :show-value="true"
                            style="height: 20px; width: 140px; font-size: 0.7rem"
                        />
                    </div>
                </div>

                <div class="header-right">
                    <div v-if="simulationStore.currentResultId" class="gene-selector-wrapper">
                        <MultiSelect
                            v-model="viewerStore.selectedGenes"
                            :options="scheduleStore.allGenes || []"
                            :disabled="isUiDisabled"
                            size="small"
                            placeholder="Filter genes..."
                            :max-selected-labels="3"
                            class="dropdown-small"
                            style="width: 620px; font-size: 0.75rem"
                            filter
                            :virtual-scroller-options="{ itemSize: 44 }"
                            :loading="simulationStore.isFetchingTimeseries"
                        >
                        <template #value="{ value }">
                            <div class="chip-container">
                                <span
                                    v-for="geneId in value"
                                    :key="geneId"
                                    class="custom-gene-chip"
                                    :style="{ backgroundColor: scheduleStore.geneColours?.[geneId], borderColor: scheduleStore.geneColours?.[geneId] }"
                                >
                                    {{ geneId }}
                                    <i 
                                        class="pi pi-times"
                                        @click.stop="viewerStore.selectedGenes = viewerStore.selectedGenes.filter(g => g !== geneId)"
                                        style="cursor: pointer; margin-left: 0.25rem; font-size: 0.6rem"
                                    />
                                </span>
                            </div>
                        </template>
                        <template #option="slotProps">
                            <div style="font-size: 0.75rem; display: flex; align-items: center; gap: 0.5rem">
                                <span
                                    style="width: 12px; height: 12px; border-radius: 3px; flex-shrink: 0; border: 1px solid"
                                    :style="{ backgroundColor: scheduleStore.geneColours?.[slotProps.option], borderColor: scheduleStore.geneColours?.[slotProps.option] }"
                                />
                                {{ slotProps.option }}
                            </div>
                        </template>
                    </MultiSelect>
                    </div>

                    <Button
                        v-if="simulationStore.currentResultId"
                        icon="pi pi-sliders-v"
                        :disabled="isUiDisabled"
                        size="small"
                        text
                        @click="(e) => trackSettingsPanel.toggle(e)"
                        title="Track settings"
                    />
                    <OverlayPanel ref="trackSettingsPanel" :show-close-button="false">
                        <div class="track-settings">
                            <h4>Display Tracks</h4>
                            <div class="track-checkbox-list">
                                <div v-for="option in trackOptions" :key="option.value" class="track-checkbox-item">
                                    <Checkbox
                                        :model-value="selectedTracks"
                                        :value="option.value"
                                        :disabled="selectedTracks.length === 1 && selectedTracks.includes(option.value)"
                                        @update:model-value="(val) => {
                                            if (val.length > 0) {
                                                selectedTracks = val
                                            }
                                        }"
                                    />
                                    <label style="margin-left: 0.5rem">{{ option.label }}</label>
                                </div>
                            </div>
                        </div>
                    </OverlayPanel>

                    <Button
                        v-if="simulationStore.currentResultId"
                        icon="pi pi-times"
                        :disabled="isUiDisabled"
                        size="small"
                        severity="danger"
                        text
                        @click="clearSimulation"
                        title="Clear loaded simulation"
                    />

                    <Button
                        :icon="isFullscreen ? 'pi pi-window-minimize' : 'pi pi-window-maximize'"
                        :title="isFullscreen ? 'Exit fullscreen (ESC)' : 'Enter fullscreen'"
                        size="small"
                        text
                        @click="toggleFullscreen"
                    />
                </div>
            </div>
        </div>

        <div class="chart-wrapper">
            <div ref="containerRef" class="chart-container"></div>
            
            <div 
                v-if="!scheduleStore.isLoaded && !isScheduleLoading"
                class="chart-overlay"
            >
                <div class="overlay-text">No schedule is loaded</div>
            </div>
        </div>

        <!-- Overlays cover entire viewer (header + chart) -->
        <div v-if="isScheduleLoading" class="loading-overlay">
            <div class="loading-card">
                <ProgressSpinner style="width: 50px; height: 50px" stroke-width="3" />
                <div class="loading-text">Loading schedule...</div>
            </div>
        </div>

        <div v-if="simulationStore.isLoadingResult" class="loading-overlay">
            <div class="loading-card">
                <ProgressSpinner style="width: 50px; height: 50px" stroke-width="3" />
                <div class="loading-text">Loading result...</div>
            </div>
        </div>

        <div v-if="isFirstTimeseriesFetch" class="loading-overlay">
            <div class="loading-card">
                <ProgressSpinner style="width: 50px; height: 50px" stroke-width="3" />
                <div class="loading-text">Loading timeseries...</div>
            </div>
        </div>
        </div>
    </Teleport>
</template>

<style>
/* Global styles (not scoped) - for overlays appended to body */
.p-select-overlay,
.p-multiselect-overlay,
.p-overlaypanel,
.p-component-overlay,
[data-pc-section="root"][role="dialog"],
[data-pc-name="overlaypanel"] {
    z-index: 10000 !important;
}
</style>

<style scoped>
/* Component-specific layout */
.simulation-viewer {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    background: var(--p-surface-ground);
    overflow: hidden;
    position: relative;
}

.card-header-row {
    display: flex;
    gap: var(--spacing-md);
    align-items: center;
    justify-content: space-between;
}

.card-header {
    background: var(--p-surface-ground);
    z-index: 10;
    position: relative;
}

.header-left {
    display: flex;
    gap: var(--spacing-md);
    align-items: center;
}

.progress-wrapper {
    display: flex;
    align-items: center;
}

.header-right {
    display: flex;
    gap: var(--spacing-md);
    align-items: center;
}

.chart-wrapper {
    flex: 1;
    min-height: 0;
    width: 100%;
    position: relative;
}

.chart-container {
    width: 100%;
    height: 100%;
}

.results-control {
    display: flex;
    gap: var(--spacing-md);
    align-items: center;
    flex: 1;
    margin-right: var(--spacing-1xl);
}

/* Domain-specific overlay */
.chart-overlay {
    position: absolute;
    inset: 0;
    background: var(--p-overlay-ground);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
}

.overlay-text {
    font-size: var(--font-size-xl);
    color: var(--p-text-color-secondary);
}

/* Fullscreen mode */
.simulation-viewer.fullscreen-mode {
    position: fixed;
    inset: 0;
    width: 100vw;
    height: 100vh;
    z-index: 9999;
    border-radius: 0;
    background: var(--p-surface-ground);
}

.simulation-viewer.fullscreen-mode .card-header {
    background: var(--p-surface-0);
    border-bottom: 1px solid var(--p-surface-border);
}

/* Gene-specific chip styling (dynamic colors) */
.chip-container {
    display: flex;
    min-height: 26px;
    max-height: 26px;
    overflow-y: auto;
}

.custom-gene-chip {
    color: white;
    padding: var(--spacing-sm) var(--spacing-sm);
    border-radius: var(--border-radius-lg);
    font-size: var(--font-size-xs);
    border: 1px solid;
}

/* Smaller chips in track selector */
:deep(.dropdown-small.p-multiselect .p-chip) {
    padding: 0.25rem 0.5rem !important;
    margin: 0.25rem !important;
    font-size: 0.7rem !important;
}

/* Track settings panel styling */
.track-settings {
    min-width: 200px;
}

.track-settings h4 {
    margin: 0 0 0.75rem 0;
    font-size: 0.875rem;
    font-weight: normal;
}

.track-checkbox-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
}

.track-checkbox-item {
    display: flex;
    align-items: center;
    font-size: 0.8rem;
}

:deep(.run-simulation-btn .p-button-label) {
    font-weight: 400 !important;
    font-family: inherit;
}
</style>
