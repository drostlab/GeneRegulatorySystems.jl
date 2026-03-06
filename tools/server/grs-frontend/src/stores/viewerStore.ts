/**
 * Viewer Synchronisation Store
 * 
 * Tracks current playback timepoint and computes expression values at that timepoint,
 * averaged across branches. Used to sync trajectory viewer with network diagram.
 */

import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { type SpeciesType } from '@/types'
import { getPathsForSegmentIds, getModelPathAtTime, getGeneFromSpeciesName, getActivePathsAtTime } from '@/types/schedule'
import { useScheduleStore } from './scheduleStore'
import { useSimulationStore } from './simulationStore'

export const useViewerStore = defineStore('viewer', () => {
    const currentTimepoint = ref<number>(0)
    const selectedGenes = ref<string[]>([])
    const selectedSpeciesNodes = ref<string[]>([])
    const selectedSpeciesTypes = ref<SpeciesType[]>([])
    const selectedSegmentIds = ref<Set<number> | null>(null)
    /** Model path of the rectangle segment currently hovered (null when not hovering). */
    const hoveredRectModelPath = ref<string | null>(null)
    /** Execution path of the hovered rect branch (null when not hovering). */
    const hoveredExecutionPath = ref<string | null>(null)
    /** Model path of the instant annotation currently hovered (null when not hovering). */
    const hoveredInstantModelPath = ref<string | null>(null)

    /**
     * Active model path driving the network overlay.
     * Only rect hover changes this (not instants); falls back to cursor timepoint.
     */
    const activeModelPath = computed((): string | null => {
        if (hoveredRectModelPath.value) return hoveredRectModelPath.value
        const scheduleStore = useScheduleStore()
        const segments = scheduleStore.segments
        if (!segments.length) return null
        return getModelPathAtTime(segments, currentTimepoint.value)
    })

    /**
     * Model path to highlight in the schedule editor.
     * Instant hover takes priority when present, otherwise follows rect hover.
     * Never falls back to timepoint — only set during explicit hover.
     */
    const editorHighlightModelPath = computed((): string | null => {
        return hoveredInstantModelPath.value ?? hoveredRectModelPath.value
    })

    const selectedPaths = computed((): Set<string> | null => {
        if (!selectedSegmentIds.value) return null
        const scheduleStore = useScheduleStore()
        const segments = scheduleStore.segments
        if (!segments.length) return null
        return getPathsForSegmentIds(segments, selectedSegmentIds.value)
    })

    /**
     * Protein count per gene at the current timepoint.
     * Priority: hovered execution path > selected segment paths > active paths at t.
     */
    const proteinCountsAtTimepoint = computed((): Record<string, number> => {
        const simulationStore = useSimulationStore()
        const ts = simulationStore.timeseries
        if (!ts) return {}

        const t = currentTimepoint.value
        const scheduleStore = useScheduleStore()

        // Priority 1: a rect branch is hovered — filter to exactly that execution path
        const filterPath = hoveredExecutionPath.value

        // Priority 2: a segment is selected — restrict to its execution paths
        const filterPaths: Set<string> | null = filterPath
            ? null
            : selectedPaths.value ?? getActivePathsAtTime(scheduleStore.segments, t)

        const geneSums: Record<string, number> = {}
        const geneCounts: Record<string, number> = {}

        for (const [species, pathData] of Object.entries(ts)) {
            if (!species.endsWith('.proteins')) continue
            const gene = getGeneFromSpeciesName(species)
            if (!gene) continue

            for (const [path, series] of Object.entries(pathData)) {
                if (filterPath && path !== filterPath) continue
                if (filterPaths && !filterPaths.has(path)) continue
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

    /** Select all timeline segments belonging to a given execution path. */
    function selectExecutionPath(executionPath: string): void {
        const scheduleStore = useScheduleStore()
        const matchIds = new Set(
            scheduleStore.segments
                .filter(s => s.execution_path === executionPath)
                .map(s => s.id)
        )
        selectedSegmentIds.value = matchIds.size > 0 ? matchIds : null
    }

    function setHoveredRectModel(path: string | null, executionPath: string | null = null): void {
        hoveredRectModelPath.value = path
        hoveredExecutionPath.value = executionPath
    }

    function setHoveredInstantModel(path: string | null): void {
        hoveredInstantModelPath.value = path
    }

    function reset(): void {
        currentTimepoint.value = 0
        selectedGenes.value = []
        selectedSpeciesNodes.value = []
        selectedSegmentIds.value = null
        hoveredRectModelPath.value = null
        hoveredInstantModelPath.value = null
        hoveredExecutionPath.value = null
    }

    return {
        currentTimepoint,
        selectedGenes,
        selectedSpeciesNodes,
        selectedSpeciesTypes,
        selectedSegmentIds,
        hoveredExecutionPath,
        activeModelPath,
        editorHighlightModelPath,
        selectedPaths,
        proteinCountsAtTimepoint,
        maxProteinCounts,
        setTimepoint,
        setHoveredRectModel,
        setHoveredInstantModel,
        selectSegments,
        selectExecutionPath,
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
