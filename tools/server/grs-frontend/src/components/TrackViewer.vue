<script setup lang="ts">
/**
 * TrackViewer Component
 *
 * Responsibilities:
 * - UI to run simulations (with active schedule)
 * - Results browser (list + select stored results)
 * - Synchronizes simulationStore ↔ viewerStore for time axis alignment
 * - SciChart trajectory plot integration (placeholder)
 * - Error display
 *
 * Integrates with:
 * - simulationStore: run simulation, load results, WebSocket state
 * - viewerStore: time extent synchronization
 * - No direct API calls (all via store)
 */
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue'
import { useSimulationStore } from '@/stores/simulationStore'
import { useScheduleStore } from '@/stores/scheduleStore'
import { useViewerStore } from '@/stores/viewerStore'
import type { SimulationResultMetadata } from '@/types/simulation'
import { formatResultLabel } from '@/types/simulation'
import { speciesTypeLabels, DEFAULT_VISIBLE_SPECIES_TYPES } from '@/types/schedule'
import type { SpeciesType } from '@/types/schedule'
import { SPECIES_TYPES } from '@/types/schedule'
import Button from 'primevue/button'
import Select, { type SelectChangeEvent } from 'primevue/select'
import MultiSelect from 'primevue/multiselect'
import InputText from 'primevue/inputtext'
import ProgressSpinner from 'primevue/progressspinner'
import Message from 'primevue/message'
import OverlayPanel from 'primevue/overlaypanel'
import Checkbox from 'primevue/checkbox'
import * as simulationService from '@/services/simulationService'
import { MainChart } from '@/charts/MainChart'

const simulationStore = useSimulationStore()
const scheduleStore = useScheduleStore()
const viewerStore = useViewerStore()

// =====================================================================
// CONSTANTS
// =====================================================================

const DEFAULT_SELECTED_GENES_COUNT = 5

// =====================================================================
// STATE
// =====================================================================


const containerRef = ref<HTMLDivElement>()
const results = ref<SimulationResultMetadata[]>([])
const error = ref<string>('')
const isFullscreen = ref<boolean>(false)
const selectedTracks = ref<string[]>([])
const trackSettingsPanel = ref()

const chart = new MainChart()

// Separate loading states for different UI elements
const isScheduleLoading = computed(() => scheduleStore.isLoading)
const isSimulationBusy = computed(() => simulationStore.isSimulationRunning || simulationStore.isLoadingResult)

// Disable UI when any operation is in progress
const isUiDisabled = computed(() => isScheduleLoading.value || isSimulationBusy.value)

// Track visibility options - only show available tracks
const trackOptions = computed(() => {
    const options: Array<{ label: string; value: string }> = []
    
    // Only include schedule if schedule is loaded
    if (scheduleStore.isLoaded) {
        options.push({ label: 'Schedule Timeline', value: 'schedule' })
    }
    
    // Only include species types if simulation is loaded
    if (simulationStore.isLoaded) {
        SPECIES_TYPES.forEach(type => {
            options.push({ label: speciesTypeLabels[type], value: type })
        })
    }
    
    return options
})

// Auto-cleanup tracks when schedule or simulation unload
watch(
    () => ({
        scheduleLoaded: scheduleStore.isLoaded,
        simulationLoaded: simulationStore.isLoaded
    }),
    (state) => {
        const validTracks: string[] = []
        
        if (state.scheduleLoaded) {
            validTracks.push('schedule')
        }
        
        if (state.simulationLoaded) {
            SPECIES_TYPES.forEach(type => validTracks.push(type))
        }
        
        // Initialize with defaults on first load
        if (state.simulationLoaded && selectedTracks.value.length === 0) {
            const defaults: string[] = []
            if (state.scheduleLoaded) {
                defaults.push('schedule')
            }
            defaults.push(...DEFAULT_VISIBLE_SPECIES_TYPES)
            selectedTracks.value = defaults
            return
        }
        
        // Remove any selected tracks that are no longer valid
        const filtered = selectedTracks.value.filter(t => validTracks.includes(t))
        
        if (filtered.length !== selectedTracks.value.length) {
            selectedTracks.value = filtered
            updateViewerStore()
        }
    }
)

watch(
    () => ({ segments: scheduleStore.segments, metadata: scheduleStore.timeseriesMetadata }),
    ({ segments, metadata }) => {
        if (segments && segments.length > 0 && metadata) {
            chart.setScheduleData(segments, metadata)
        }
    }
)

watch(
    () => simulationStore.timeseries,
    (newTimeseries) => {
        if (newTimeseries) {
            chart.setSimulationData(newTimeseries)
        } else {
            chart.clearSimulationData()
        }
    }
)

// Auto-select genes when schedule genes become available after simulation load
watch(
    () => scheduleStore.allGenes,
    (allGenes) => {
        if (simulationStore.isLoaded && allGenes && allGenes.length > 0) {
            viewerStore.selectedGenes = allGenes.slice(0, DEFAULT_SELECTED_GENES_COUNT)
        }
    }
)

// Update viewerStore when tracks change
function updateViewerStore() {
    viewerStore.selectedSpeciesTypes = selectedTracks.value.filter(t => t !== 'schedule') as SpeciesType[]
}

async function loadResults() {
    results.value = await simulationService.fetchResultsList()
}


onMounted(async () => {
    // Load available results
    loadResults()

    // Setup trajectory chart
    await chart.init(containerRef)
    chart.setVisibleTracks(['schedule'])
    
    // Register timepoint change callback
    chart.onTimepointChange((timepoint: number) => {
        viewerStore.setTimepoint(timepoint)
    })

    // Add ESC key listener for fullscreen exit
    window.addEventListener('keydown', handleEscapeKey)
})

onBeforeUnmount(() => {
    chart.dispose()
    window.removeEventListener('keydown', handleEscapeKey)
})

// Load result. This also updates the schedule to the one that had been used to produce the result
async function loadResult(event: SelectChangeEvent) {
    // Clear simulation before loading new one
    simulationStore.clearResult()
    const selectedResultId = event.value
    chart.clear()

    await simulationStore.loadResult(selectedResultId)
}

async function runSimulation() {
    chart.clear()
    await simulationStore.runSimulation()
    // Now the simulation is loaded. the timeseries watcher will handle the update of the chart
    await loadResults()
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
    if (event.key === 'Escape' && isFullscreen.value) {
        isFullscreen.value = false
    }
}

watch(
    () => selectedTracks.value,
    (newTracks) => {
        chart.setVisibleTracks(newTracks)
        updateViewerStore()
    }
)



watch(
    () => viewerStore.selectedGenes,
    (newGenes) => {
        const visibleData = simulationStore.getTimeseries(newGenes)
        if (visibleData)
            chart.setSimulationData(visibleData)
    }
)

</script>



<template>
    <Teleport to="body" :disabled="!isFullscreen">
        <div class="simulation-viewer" :class="{ 'fullscreen-mode': isFullscreen }">
        <div class="card-header">
            <div class="card-header-row">
                <!-- Left Section: Results & Run Button -->
                <div class="header-left">
                    <!-- Results Selector / Running Status -->
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

                    <!-- Run Simulation Button -->
                    <Button
                        :label="simulationStore.isSimulationRunning ? 'Running Simulation' : 'Run Simulation'"
                        :icon="simulationStore.isSimulationRunning ? 'pi pi-spin pi-spinner' : 'pi pi-play-circle'"
                        :disabled="isUiDisabled"
                        size="small"
                        severity="success"
                        @click="runSimulation"
                        class="run-simulation-btn"
                    />
                </div>

                <!-- Right Section: Simulation Controls & Fullscreen -->
                <div class="header-right">
                    <!-- Gene Filter Selector -->
                    <MultiSelect
                        v-if="simulationStore.currentResultId"
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

                    <!-- Track Settings Button -->
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

                    <!-- Clear Simulation Button -->
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

                    <!-- Fullscreen Toggle Button -->
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

        <!-- SciChart Canvas Container -->
        <div class="chart-wrapper">
            <div ref="containerRef" class="chart-container"></div>
            
            <!-- Overlay when no schedule is loaded -->
            <div 
                v-if="!scheduleStore.isLoaded && !isScheduleLoading"
                class="chart-overlay"
            >
                <div class="overlay-text">No schedule is loaded</div>
            </div>
        </div>

        <!-- Status Messages -->
        <Message
            v-if="error"
            severity="error"
            :text="error"
        />

        <!-- Loading Overlay -->
        <div v-if="isScheduleLoading || simulationStore.isLoadingResult" class="loading-overlay">
            <div v-if="simulationStore.isLoadingResult" class="loading-card">
                <ProgressSpinner style="width: 50px; height: 50px" stroke-width="3" />
                <div class="loading-text">Loading result...</div>
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
