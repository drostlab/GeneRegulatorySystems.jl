/**
 * Viewer Synchronisation Store
 * 
 * Tracks current playback timepoint and computes expression values at that timepoint,
 * averaged across branches. Used to sync trajectory viewer with network diagram.
 */

import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import type { Timeseries } from '@/types/simulation'

export const useViewerStore = defineStore('viewer', () => {
    // Current timepoint in simulation (set by trajectory chart scrubbing)
    const currentTimepoint = ref<number>(0)
    
    // Timeseries data (loaded when simulation result is loaded)
    const timeseries = ref<Timeseries | null>(null)
    
    // Pre-computed maximum values for each species (for normalization)
    // Structure: speciesId → max value across entire simulation
    const maxValues = ref<Record<string, number>>({})

    /**
     * Compute expression values at current timepoint, averaged across branches
     * Returns: speciesId → averaged value
     */
    const speciesValuesAtTimepoint = computed(() => {
        if (!timeseries.value) return {}
        
        const result: Record<string, number> = {}
        
        for (const [speciesId, paths] of Object.entries(timeseries.value)) {
            const values: number[] = []
            
            // Collect values from all paths at current timepoint (or nearest)
            for (const timeSeries of Object.values(paths)) {
                const value = getValueAtTimepoint(timeSeries as Array<[number, number]>, currentTimepoint.value)
                if (value !== null) {
                    values.push(value)
                }
            }
            
            // Average across paths
            if (values.length > 0) {
                result[speciesId] = values.reduce((a, b) => a + b, 0) / values.length
            }
        }
        
        return result
    })

    /**
     * Get normalized value (0-1) for a species at current timepoint
     */
    function getNormalizedValue(speciesId: string): number {
        const value = speciesValuesAtTimepoint.value[speciesId] ?? 0
        const max = maxValues.value[speciesId] ?? 1
        const normalized = max > 0 ? value / max : 0
        
        // Log species lookups to debug mismatch
        if (normalized === 0 && speciesId.includes('gene')) {
            console.debug('[viewerStore] Species lookup', {
                requestedSpeciesId: speciesId,
                value,
                max,
                normalized,
                allAvailableSpecies: Object.keys(speciesValuesAtTimepoint.value)
            })
        }
        
        return normalized
    }

    /**
     * Initialize store with timeseries data
     * Pre-computes max values for normalization
     */
    function initializeWithTimeseries(newTimeseries: Timeseries): void {
        console.debug('initializeWithTimeseries called', {
            speciesCount: Object.keys(newTimeseries).length,
            firstSpecies: Object.keys(newTimeseries)[0]
        })
        timeseries.value = newTimeseries
        maxValues.value = computeMaxValues(newTimeseries)
        currentTimepoint.value = 0
        console.debug('initializeWithTimeseries complete', {
            maxValuesCount: Object.keys(maxValues.value).length
        })
    }

    /**
     * Update current timepoint
     */
    function setTimepoint(t: number): void {
        console.debug('setTimepoint called', { t })
        currentTimepoint.value = t
    }

    /**
     * Reset store
     */
    function reset(): void {
        currentTimepoint.value = 0
        timeseries.value = null
        maxValues.value = {}
    }

    return {
        currentTimepoint,
        timeseries,
        maxValues,
        speciesValuesAtTimepoint,
        getNormalizedValue,
        initializeWithTimeseries,
        setTimepoint,
        reset
    }
})

/**
 * Get value from timeseries at given timepoint
 * Uses nearest-neighbour lookup (no interpolation)
 */
function getValueAtTimepoint(timeSeries: Array<[number, number]>, timepoint: number): number | null {
    if (timeSeries.length === 0) return null
    
    // Find nearest timepoint
    let nearest = timeSeries[0]!
    let minDist = Math.abs(timeSeries[0]![0] - timepoint)
    
    for (const point of timeSeries) {
        const dist = Math.abs(point[0] - timepoint)
        if (dist < minDist) {
            minDist = dist
            nearest = point
        }
    }
    
    return nearest[1]
}

/**
 * Compute maximum value for each species across entire timeseries
 */
function computeMaxValues(ts: Timeseries): Record<string, number> {
    const maxVals: Record<string, number> = {}
    
    for (const [speciesId, paths] of Object.entries(ts)) {
        let max = 0
        for (const timeSeries of Object.values(paths)) {
            for (const [_, value] of timeSeries as Array<[number, number]>) {
                max = Math.max(max, value)
            }
        }
        maxVals[speciesId] = max
    }
    
    return maxVals
}
