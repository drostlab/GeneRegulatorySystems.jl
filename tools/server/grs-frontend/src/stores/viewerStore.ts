/**
 * Viewer Synchronisation Store
 * 
 * Tracks current playback timepoint and computes expression values at that timepoint,
 * averaged across branches. Used to sync trajectory viewer with network diagram.
 */

import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { type SpeciesType } from '@/types'
import { getPathsForSegmentIds } from '@/types/schedule'
import { useScheduleStore } from './scheduleStore'

export const useViewerStore = defineStore('viewer', () => {
    const currentTimepoint = ref<number>(0)
    const selectedGenes = ref<string[]>([])
    const selectedSpeciesTypes = ref<SpeciesType[]>([])
    const selectedSegmentIds = ref<Set<number> | null>(null)
    const activeModelPath = ref<string | null>(null)

    const selectedPaths = computed((): Set<string> | null => {
        if (!selectedSegmentIds.value) return null
        const scheduleStore = useScheduleStore()
        const segments = scheduleStore.segments
        if (!segments.length) return null
        return getPathsForSegmentIds(segments, selectedSegmentIds.value)
    })

    function setTimepoint(t: number): void {
        currentTimepoint.value = t
    }

    function selectSegments(ids: Set<number> | null): void {
        selectedSegmentIds.value = ids
    }

    function setActiveModelPath(path: string | null): void {
        activeModelPath.value = path
    }

    function reset(): void {
        currentTimepoint.value = 0
        selectedSegmentIds.value = null
        activeModelPath.value = null
    }

    return {
        currentTimepoint,
        selectedGenes,
        selectedSpeciesTypes,
        selectedSegmentIds,
        activeModelPath,
        selectedPaths,
        setTimepoint,
        selectSegments,
        setActiveModelPath,
        reset
    }
})
