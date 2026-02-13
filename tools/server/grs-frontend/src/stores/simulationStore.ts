import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { useScheduleStore } from './scheduleStore'
import type { SimulationResult } from '@/types/simulation'
import { formatResultLabel } from '@/types/simulation'
import * as simulationService from '@/services/simulationService'

/**
 * Simulation Store – Manages simulation results and active result state
 *
 * Responsibilities:
 * - API calls: run simulation (synchronous), load stored results
 * - Maintain single active result (either running or loaded for playback)
 * - Track simulation running state via status field
 *
 * Architecture:
 * - No WebSocket needed (simulations run synchronously)
 * - Results are returned fully loaded with all frames
 * - currentResult: fully loaded with frames (for visualization)
 *
 * Does NOT manage:
 * - Schedule data (that's scheduleStore)
 * - Results list for dropdown (that's component state in SimulationViewer)
 * - UI visualization state like time cursor or zoom (that's viewerStore)
 * - Schedule editing or persistence (that's scheduleStore)
 *
 * Data Flow:
 * 1. User clicks "Run Simulation" → POST /api/simulations/run
 * 2. Server runs simulation synchronously, returns full result with frames
 * 3. currentResult is set with all data
 * 4. computeTimeseries from currentResult.data.frames for visualization
 * 5. loadResult(id) → loads stored result and sets as currentResult
 */
export const useSimulationStore = defineStore(
    'simulation',
    () => {
        // =====================================================================
        // STATE
        // =====================================================================

        // Currently active result (either running or loaded for playback) - fully loaded with frames
        const currentResult = ref<SimulationResult | null>(null)
        const isSimulationRunning = ref(false)
        const isLoadingResult = ref(false)

        const currentResultId = computed(() => {
            return currentResult.value?.id ?? null
        })

        const currentResultLabel = computed(() => {
            return formatResultLabel(currentResult.value)
        })

        const isLoaded = computed(() => {
            return currentResult.value !== null
        })

        const timeseries = computed(() => {
            return currentResult.value?.data.timeseries ?? null
        })

        /**
         * Get timeseries filtered by genes and paths
         * 
         * @param genes - Array of gene symbols to include. null/undefined includes all genes. Empty array includes none.
         * @param paths - Array of path IDs to include. null/undefined includes all paths. Empty array includes none.
         * @returns Filtered timeseries data, or null if no current result
         */
        function getTimeseries(genes?: string[] | null, paths?: string[] | null) {
            // TODO: lazy retrieval of data from server
            if (!timeseries.value) {
                return null
            }

            const scheduleStore = useScheduleStore()
            
            // Explicit behavior: null/undefined = include all, empty array = include none
            if (genes !== null && genes !== undefined && genes.length === 0) {
                return {}  // Empty array means exclude all genes
            }
            if (paths !== null && paths !== undefined && paths.length === 0) {
                return {}  // Empty array means exclude all paths
            }
            
            // Build set of species IDs to include
            const speciesIds = new Set(
                genes === null || genes === undefined
                    ? Object.keys(timeseries.value)
                    : genes.flatMap(gene => scheduleStore.getSpeciesForGeneId(gene))
            )
            
            const pathSet = paths === null || paths === undefined 
                ? null 
                : new Set(paths)

            // Vectorized filtering: filter species, then filter paths for each species
            return Object.fromEntries(
                Object.entries(timeseries.value)
                    .filter(([species]) => speciesIds.has(species))
                    .map(([species, pathData]) => [
                        species,
                        Object.fromEntries(
                            Object.entries(pathData)
                                .filter(([path]) => pathSet === null || pathSet.has(path))
                        )
                    ])
            ) as typeof timeseries.value
        }

        async function loadResult(resultId: string): Promise<SimulationResult> {
            isLoadingResult.value = true
            try {
                const result = await simulationService.loadSimulationResult(resultId)
                currentResult.value = result
                const scheduleStore = useScheduleStore()
                await scheduleStore.loadScheduleBySpec(result.schedule_spec, result.schedule_name)

                return result
            } finally {
                isLoadingResult.value = false
            }
        }

        /**
         * Run simulation for the active schedule
         */
        async function runSimulation(): Promise<SimulationResult> {
            const scheduleStore = useScheduleStore()

            if (!scheduleStore.schedule) {
                throw new Error('No running schedule selected')
            }

            if (isSimulationRunning.value) {
                throw new Error('Simulation already running')
            }

            currentResult.value = null
            isSimulationRunning.value = true

            try {
                const result = await simulationService.runSimulation(scheduleStore.schedule.name, scheduleStore.schedule.spec)
                currentResult.value = result
                return currentResult.value
            } finally {
                isSimulationRunning.value = false
            }
        }


        /**
         * Reset all state
         */
        function reset() {
            currentResult.value = null
        }

        /**
         * Clear the currently loaded result
         */
        function clearResult() {
            currentResult.value = null
        }


        return {
            // State
            currentResult,
            isSimulationRunning,
            isLoadingResult,
            currentResultId,

            // Computed
            currentResultLabel,
            isLoaded,
            timeseries,

            // Methods
            getTimeseries,

            // API
            runSimulation,
            loadResult,

            // Cleanup
            reset,
            clearResult
        }
    }
)
