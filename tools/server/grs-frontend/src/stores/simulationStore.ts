import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { useScheduleStore } from './scheduleStore'
import type { SimulationResult, SimulationResultMetadata, TimeseriesData } from '@/types/simulation'
import { formatResultLabel } from '@/types/simulation'
import * as simulationService from '@/services/simulationService'

/**
 * Simulation Store -- manages simulation results with lazy per-gene timeseries loading.
 *
 * Architecture:
 * - `loadResult(id)` loads metadata only (no timeseries data)
 * - `fetchGeneTimeseries(genes)` fetches species for those genes from the server
 *   and merges into `timeseriesCache`
 * - `timeseries` computed exposes the accumulated cache
 * - `runSimulation` loads everything eagerly (result includes full data)
 *
 * Consumers call `getTimeseries(genes, paths)` which filters the cache.
 */
export const useSimulationStore = defineStore(
    'simulation',
    () => {
        // =====================================================================
        // STATE
        // =====================================================================

        const currentResult = ref<SimulationResultMetadata | SimulationResult | null>(null)
        const isSimulationRunning = ref(false)
        const isLoadingResult = ref(false)

        /** Accumulated timeseries data, merged across per-gene fetches. */
        const timeseriesCache = ref<TimeseriesData>({})

        /** Set of genes already fetched (avoids duplicate requests). */
        const fetchedGenes = ref<Set<string>>(new Set())

        /** Currently in-flight gene fetch (prevents concurrent fetches). */
        const isFetchingTimeseries = ref(false)

        const currentResultId = computed(() => {
            return currentResult.value?.id ?? null
        })

        const currentResultLabel = computed(() => {
            return formatResultLabel(currentResult.value)
        })

        const isLoaded = computed(() => {
            return currentResult.value !== null
        })

        const timeseries = computed((): TimeseriesData | null => {
            if (!currentResult.value) return null
            return Object.keys(timeseriesCache.value).length > 0 ? timeseriesCache.value : null
        })

        /**
         * Lazily fetch timeseries for the given genes.
         * Only fetches genes not already in cache. Merges results into timeseriesCache.
         */
        async function fetchGeneTimeseries(genes: string[]): Promise<void> {
            const resultId = currentResultId.value
            if (!resultId) return

            const scheduleStore = useScheduleStore()
            const newGenes = genes.filter(g => !fetchedGenes.value.has(g))
            if (newGenes.length === 0) return

            // Collect all species for the new genes
            const species = newGenes.flatMap(gene => scheduleStore.getSpeciesForGeneId(gene))
            if (species.length === 0) {
                newGenes.forEach(g => fetchedGenes.value.add(g))
                return
            }

            isFetchingTimeseries.value = true
            console.debug(`[SimulationStore] Fetching timeseries for genes: [${newGenes.join(', ')}] (${species.length} species)`)

            const data = await simulationService.fetchTimeseriesForSpecies(resultId, species)

            // Merge into cache
            const merged = { ...timeseriesCache.value }
            for (const [speciesName, pathData] of Object.entries(data)) {
                merged[speciesName] = pathData
            }
            timeseriesCache.value = merged

            newGenes.forEach(g => fetchedGenes.value.add(g))
            isFetchingTimeseries.value = false

            console.debug(`[SimulationStore] Cache now has ${Object.keys(timeseriesCache.value).length} species`)
        }

        /**
         * Get timeseries filtered by genes and paths.
         * Returns data from cache only -- call fetchGeneTimeseries first.
         */
        function getTimeseries(genes?: string[] | null, paths?: string[] | null) {
            if (!timeseries.value) return null

            const scheduleStore = useScheduleStore()

            if (genes !== null && genes !== undefined && genes.length === 0) return {}
            if (paths !== null && paths !== undefined && paths.length === 0) return {}

            const speciesIds = new Set(
                genes === null || genes === undefined
                    ? Object.keys(timeseries.value)
                    : genes.flatMap(gene => scheduleStore.getSpeciesForGeneId(gene))
            )

            const pathSet = paths === null || paths === undefined
                ? null
                : new Set(paths)

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
            ) as TimeseriesData
        }

        async function loadResult(resultId: string): Promise<void> {
            isLoadingResult.value = true
            clearTimeseriesCache()
            const metadata = await simulationService.pollResult(resultId)
            if (!metadata) throw new Error('Result not found')
            currentResult.value = metadata

            const scheduleStore = useScheduleStore()
            await scheduleStore.loadScheduleBySpec(metadata.schedule_spec, metadata.schedule_name)
            isLoadingResult.value = false
        }

        async function runSimulation(): Promise<SimulationResult> {
            const scheduleStore = useScheduleStore()
            if (!scheduleStore.schedule) throw new Error('No running schedule selected')
            if (isSimulationRunning.value) throw new Error('Simulation already running')

            clearTimeseriesCache()
            currentResult.value = null
            isSimulationRunning.value = true

            const result = await simulationService.runSimulation(scheduleStore.schedule.name, scheduleStore.schedule.spec)
            currentResult.value = result

            // Eagerly populate cache from full result
            if (result.data?.timeseries) {
                timeseriesCache.value = result.data.timeseries
                // Mark all genes as fetched
                const allGenes = scheduleStore.allGenes ?? []
                allGenes.forEach(g => fetchedGenes.value.add(g))
            }

            isSimulationRunning.value = false
            return result
        }

        function clearTimeseriesCache(): void {
            timeseriesCache.value = {}
            fetchedGenes.value = new Set()
        }

        function reset(): void {
            currentResult.value = null
            clearTimeseriesCache()
        }

        function clearResult(): void {
            currentResult.value = null
            clearTimeseriesCache()
        }

        return {
            currentResult,
            isSimulationRunning,
            isLoadingResult,
            isFetchingTimeseries,
            currentResultId,
            currentResultLabel,
            isLoaded,
            timeseries,
            fetchedGenes,
            getTimeseries,
            fetchGeneTimeseries,
            runSimulation,
            loadResult,
            reset,
            clearResult,
        }
    }
)
