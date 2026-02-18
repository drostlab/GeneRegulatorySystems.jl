/**
 * Viewer Synchronisation Store
 * 
 * Tracks current playback timepoint and computes expression values at that timepoint,
 * averaged across branches. Used to sync trajectory viewer with network diagram.
 */

import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { type SpeciesType } from '@/types'
import { getPathsForSegmentIds, getModelPathAtTime, getGeneFromSpeciesName } from '@/types/schedule'
import { useScheduleStore } from './scheduleStore'
import { useSimulationStore } from './simulationStore'

export const useViewerStore = defineStore('viewer', () => {
    const currentTimepoint = ref<number>(0)
    const selectedGenes = ref<string[]>([])
    const selectedSpeciesTypes = ref<SpeciesType[]>([])
    const selectedSegmentIds = ref<Set<number> | null>(null)
    /** Model path currently hovered in the timeline panel (null when not hovering). */
    const hoveredModelPath = ref<string | null>(null)

    /** Active model path: hovered model takes priority, else derived from current timepoint. */
    const activeModelPath = computed((): string | null => {
        if (hoveredModelPath.value) return hoveredModelPath.value
        const scheduleStore = useScheduleStore()
        const segments = scheduleStore.segments
        if (!segments.length) return null
        return getModelPathAtTime(segments, currentTimepoint.value)
    })

    const selectedPaths = computed((): Set<string> | null => {
        if (!selectedSegmentIds.value) return null
        const scheduleStore = useScheduleStore()
        const segments = scheduleStore.segments
        if (!segments.length) return null
        return getPathsForSegmentIds(segments, selectedSegmentIds.value)
    })

    /**
     * Protein count per gene at the current timepoint, averaged across paths.
     * Returns Record<geneName, averageCount>.
     */
    const proteinCountsAtTimepoint = computed((): Record<string, number> => {
        const simulationStore = useSimulationStore()
        const ts = simulationStore.timeseries
        if (!ts) return {}

        const t = currentTimepoint.value
        const geneSums: Record<string, number> = {}
        const geneCounts: Record<string, number> = {}

        for (const [species, pathData] of Object.entries(ts)) {
            if (!species.endsWith('.proteins')) continue
            const gene = getGeneFromSpeciesName(species)
            if (!gene) continue

            for (const series of Object.values(pathData)) {
                const value = sampleAtTime(series, t)
                geneSums[gene] = (geneSums[gene] ?? 0) + value
                geneCounts[gene] = (geneCounts[gene] ?? 0) + 1
            }
        }

        const result: Record<string, number> = {}
        for (const gene of Object.keys(geneSums)) {
            result[gene] = geneSums[gene]! / (geneCounts[gene] ?? 1)
        }
        return result
    })

    /**
     * Max protein count per gene across the entire timeseries (for normalisation).
     */
    const maxProteinCounts = computed((): Record<string, number> => {
        const simulationStore = useSimulationStore()
        const ts = simulationStore.timeseries
        if (!ts) return {}

        const result: Record<string, number> = {}

        for (const [species, pathData] of Object.entries(ts)) {
            if (!species.endsWith('.proteins')) continue
            const gene = getGeneFromSpeciesName(species)
            if (!gene) continue

            for (const series of Object.values(pathData)) {
                for (const [, v] of series) {
                    result[gene] = Math.max(result[gene] ?? 0, v)
                }
            }
        }
        return result
    })

    function setTimepoint(t: number): void {
        currentTimepoint.value = t
    }

    function selectSegments(ids: Set<number> | null): void {
        selectedSegmentIds.value = ids
    }

    function setHoveredModelPath(path: string | null): void {
        hoveredModelPath.value = path
    }

    function reset(): void {
        currentTimepoint.value = 0
        selectedSegmentIds.value = null
        hoveredModelPath.value = null
    }

    return {
        currentTimepoint,
        selectedGenes,
        selectedSpeciesTypes,
        selectedSegmentIds,
        hoveredModelPath,
        activeModelPath,
        selectedPaths,
        proteinCountsAtTimepoint,
        maxProteinCounts,
        setTimepoint,
        setHoveredModelPath,
        selectSegments,
        reset
    }
})

/**
 * Binary search to sample a timeseries value at a given time.
 */
function sampleAtTime(series: Array<[number, number]>, t: number): number {
    if (series.length === 0) return 0
    if (t <= series[0]![0]) return series[0]![1]
    if (t >= series[series.length - 1]![0]) return series[series.length - 1]![1]

    let lo = 0
    let hi = series.length - 1
    while (lo < hi - 1) {
        const mid = (lo + hi) >> 1
        if (series[mid]![0] <= t) lo = mid
        else hi = mid
    }
    // Linear interpolation
    const [t0, v0] = series[lo]!
    const [t1, v1] = series[hi]!
    if (t1 === t0) return v0
    const frac = (t - t0) / (t1 - t0)
    return v0 + frac * (v1 - v0)
}
