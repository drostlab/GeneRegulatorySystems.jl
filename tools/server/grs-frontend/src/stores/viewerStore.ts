/**
 * Viewer Synchronisation Store
 * 
 * Tracks current playback timepoint and computes expression values at that timepoint,
 * averaged across branches. Used to sync trajectory viewer with network diagram.
 */

import { ref } from 'vue'
import { defineStore } from 'pinia'
import { type SpeciesType } from '@/types'

export const useViewerStore = defineStore('viewer', () => {
    // Current timepoint in simulation (set by trajectory chart scrubbing)
    const currentTimepoint = ref<number>(0)
    

    // Gene filter state - which genes to display (empty array = all genes)
    const selectedGenes = ref<string[]>([])

    // Species type filter state - which species types to display (one-way read-out from SimulationViewer)
    const selectedSpeciesTypes = ref<SpeciesType[]>([])


    /**
     * Update current timepoint
     */
    function setTimepoint(t: number): void {
        currentTimepoint.value = t
    }

    /**
     * Reset store and remove simulation tracks from visibility
     */
    function reset(): void {
        currentTimepoint.value = 0
        // Remove simulation tracks when resetting
    }

    return {
        currentTimepoint,
        selectedGenes,
        selectedSpeciesTypes,
        setTimepoint,
        reset
    }
})
