/**
 * Simulation Service – API integration for simulation operations
 *
 * Responsibilities:
 * - Fetch stored simulation result metadata (without frames)
 * - Load full simulation result (metadata + frames combined)
 * - Run simulations (handled via WebSocket in simulationStore)
 *
 * Used by: simulationStore
 */

import { apiFetchJson } from '@/utils/api'
import type { SimulationResultMetadata, SimulationResult } from '@/types'

/**
 * Fetch all stored simulation results metadata, without frames data
 */
export async function fetchResultsList(): Promise<SimulationResultMetadata[]> {

    const data = await apiFetchJson<SimulationResultMetadata[]>('/simulations')

    if (!Array.isArray(data)) {
        console.warn('[simulationService] No results found or invalid format')
        return []
    }

    console.debug(`[simulationService] Loaded ${data.length} simulation results`)
    return data
}

/**
 * Load full simulation result with metadata and frames from single endpoint
 */
export async function loadSimulationResult(resultId: string): Promise<SimulationResult> {
    const result = await apiFetchJson<SimulationResult>(`/simulations/${resultId}`)
    return result
}

/**
 * Poll server for current result status
 * Used to verify if simulation is still running (timeout recovery)
 * Returns null if request fails
 */
export async function pollResult(resultId: string): Promise<SimulationResultMetadata | null> {
    try {
        const metadata = await apiFetchJson<SimulationResultMetadata>(`/simulations/${resultId}`)
        return metadata
    } catch (error) {
        console.error('[simulationService] Error polling result:', error)
        return null
    }
}

/**
 * Run a simulation with the provided schedule name and JSON
 * Accepts schedule specification as JSON instead of loading from stored schedules
 * Returns simulation result metadata (result will be streamed via WebSocket)
 */
export async function runSimulation(scheduleName: string, scheduleJson: string): Promise<SimulationResultMetadata> {
    const response = await apiFetchJson<SimulationResultMetadata>('/simulations/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            schedule_name: scheduleName,
            schedule_spec: scheduleJson
        })
    })

    if (!response.id) {
        throw new Error('Server did not return result metadata')
    }

    return response
}