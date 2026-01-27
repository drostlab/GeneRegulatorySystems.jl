<script setup lang="ts">
/**
 * SimulationViewer Component
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
import { ref, onMounted, onBeforeUnmount} from 'vue'
import { useSimulationStore } from '@/stores/simulationStore'
import { useScheduleStore } from '@/stores/scheduleStore'
import { useViewerStore } from '@/stores/viewerStore'
import { useTrajectoryChart } from '@/composables/useTrajectoryChart'
import type { SimulationResultMetadata } from '@/types/simulation'
import { timeseriesToTrackData, formatResultLabel } from '@/types/simulation'
import Button from 'primevue/button'
import Select, { type SelectChangeEvent } from 'primevue/select'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import * as simulationService from '@/services/simulationService'

const simulationStore = useSimulationStore()
const scheduleStore = useScheduleStore()
const viewerStore = useViewerStore()
const chart = useTrajectoryChart()

// =====================================================================
// STATE
// =====================================================================

const containerRef = ref<HTMLDivElement>()
const results = ref<SimulationResultMetadata[]>([])
const error = ref<string>('')
const isLoadingResult = ref<boolean>(false)



async function loadResults() {
    results.value = await simulationService.fetchResultsList()
}

function updateChart() {
    if (simulationStore.currentTimeseries && scheduleStore.geneColours) {
        const trackData = timeseriesToTrackData(
            simulationStore.currentTimeseries,
            scheduleStore.geneColours,
            scheduleStore.segments
        )
        chart.updateTrajectory(trackData)
    }
}

// /**
//  * Auto-select the latest simulation result for the given schedule name.
//  * If no result exists for that schedule, the dropdown remains empty.
//  */
// async function autoSelectLatestResult(scheduleName: string) {
//     if (!scheduleName) {
//         selectedResultId.value = ''
//         return
//     }

//     const matchingResults = results.value
//         .filter(r => r.schedule_name === scheduleName)
//         .sort((a, b) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime())

//     if (matchingResults.length > 0) {
//         selectedResultId.value = matchingResults[0]!.id
//         await loadResult()  // Await the async call
//     } else {
//         selectedResultId.value = ''
//     }
// }

onMounted(async () => {
    // Connect WebSocket on mount
    if (!simulationStore.wsConnected) 
        await simulationStore.connectWebSocket()

    // Load available results
    loadResults()

    // Setup trajectory chart
    await chart.initChart(containerRef)
    // Register frame batch callback for streaming updates
    simulationStore.onFrameBatch(updateChart)
    // Register timepoint change callback to sync with viewer store
    chart.onTimepointChange((timepoint: number) => {
        viewerStore.setTimepoint(timepoint)
    })
})

onBeforeUnmount(() => {
    chart.dispose()
})

// Load result. This also updates the schedule to the one that had been used to produce the result
async function loadResult(event: SelectChangeEvent) {
    const selectedResultId = event.value
    chart.clearChart()

    isLoadingResult.value = true
    chart.showLoader(containerRef)
    try {
        // This syncs both the schedule and loads frames
        await simulationStore.loadResult(selectedResultId)
        // Initialize viewer store with timeseries data
        if (simulationStore.currentTimeseries) {
            viewerStore.initializeWithTimeseries(simulationStore.currentTimeseries)
        }
        // Render the trajectory
        updateChart()
    } catch (err) {
        console.error('[SimulationViewer] Error loading result:', err)
    } finally {
        isLoadingResult.value = false
        chart.hideLoader(containerRef)
    }
}

async function runSimulation() {
    chart.clearChart()
    await simulationStore.runSimulation()
    await loadResults()
}


</script>



<template>
    <div class="simulation-viewer">
        <div class="header">
            <!-- Results Selector / Running Status -->
            <div class="results-control">
                <Select
                    v-if="!simulationStore.isSimulationRunning"
                    :model-value="simulationStore.currentResultId"
                    :options="results"
                    option-value="id"
                    :disabled="isLoadingResult"
                    size="small"
                    placeholder="Load simulation result..."
                    @change="loadResult"
                    class="dropdown-small"
                >
                    <template #option="slotProps">
                        <div style="font-size: 0.75rem">{{ formatResultLabel(slotProps.option) }}</div>
                    </template>
                    <template #value="slotProps">
                        <div v-if="slotProps.value" style="font-size: 0.75rem">
                            {{ formatResultLabel(results.find(r => r.id === slotProps.value)!) }}
                        </div>
                        <span v-else style="font-size: 0.75rem">Load simulation result...</span>
                    </template>
                    <template #empty>
                        <div style="font-size: 0.75rem">No available results</div>
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
                :icon="simulationStore.isSimulationRunning ? 'pi pi-spin pi-spinner' : 'pi pi-play'"
                :loading="simulationStore.isSimulationRunning"
                :disabled="!simulationStore.wsConnected || simulationStore.isSimulationRunning || isLoadingResult"
                size="small"
                severity="success"
                @click="runSimulation"
            />
        </div>

        <!-- SciChart Canvas Container -->
        <div class="chart-wrapper">
            <div ref="containerRef" class="chart-container"></div>
        </div>

        <!-- Status Messages -->
        <Message
            v-if="error"
            severity="error"
            :text="error"
        />
    </div>
</template>

<style scoped>
.simulation-viewer {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    background: var(--p-surface-ground);
    overflow: hidden;
}

.header {
    display: flex;
    flex-direction: row;
    gap: 0.75rem;
    align-items: center;
    justify-content: center;
    background: var(--p-surface-card);
    padding: 1rem;
    flex-shrink: 0;
    width: 100%;
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

:deep(.p-message) {
    flex-shrink: 0;
}

</style>
