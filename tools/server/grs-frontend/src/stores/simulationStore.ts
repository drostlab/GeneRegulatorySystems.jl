import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { useScheduleStore } from './scheduleStore'
import { useWebSocket } from '@/composables/useWebSocket'
import type { SimulationFrame } from '@/types'
import type { SimulationResult, SimulationStatus } from '@/types/simulation'
import { computeTimeseries, accumulateFrames, isResultLoaded, formatResultLabel } from '@/types/simulation'
import * as simulationService from '@/services/simulationService'

/**
 * Simulation Store – Manages WebSocket lifecycle, frame streaming, and active result
 *
 * Responsibilities:
 * - WebSocket connection & lifecycle (connect, disconnect, reconnect on failure)
 * - Frame accumulation from WebSocket into in-memory timeseries
 * - API calls: run simulation, load stored results
 * - Track simulation running state (isSimulationRunning, wsConnected)
 * - Maintain single active result (either running or loaded for playback)
 *
 * Architecture:
 * - Single persistent WebSocket connection (/ws) established on app mount
 * - Single session on backend (no session ID needed)
 * - If WebSocket disconnects, running simulation is aborted
 * - On reconnect, user must restart simulation
 * - currentResult: fully loaded with frames (for visualization)
 *
 * Does NOT manage:
 * - Schedule data (that's scheduleStore)
 * - Results list for dropdown (that's component state in SimulationViewer)
 * - UI visualization state like time cursor or zoom (that's viewerStore)
 * - Schedule editing or persistence (that's scheduleStore)
 *
 * Data Flow:
 * 1. App mounts → connectWebSocket() establishes /ws connection
 * 2. User clicks "Run Simulation" → POST /api/simulations/run
 * 3. Server starts simulation, WebSocket streams frames via streaming_callback
 * 4. Frames accumulate in currentResult (SimulationResultFull)
 * 5. computeTimeseries from currentResult.data.frames for visualization
 * 6. loadResult(id) → loads stored result and sets as currentResult
 */
export const useSimulationStore = defineStore(
    'simulation',
    () => {
        // =====================================================================
        // STATE
        // =====================================================================

        const { isConnected: wsConnected, connect: connectWs, on: onMessage } = useWebSocket()

        // Currently active result (either running or loaded for playback) - fully loaded with frames
        const currentResult = ref<SimulationResult | null>(null)

        const currentResultId = computed(() => {
            return currentResult.value?.id ?? null
        })

        const currentResultLabel = computed(() => {
            return formatResultLabel(currentResult.value)
        })


        const isSimulationRunning = computed(() => {
            return currentResult.value?.status === 'running'
        })

        const currentTimeseries = computed(() => {
            if (!currentResult.value || !isResultLoaded(currentResult.value)) {
                return {}
            }
            return computeTimeseries(currentResult.value.data.frames)
        })

        async function connectWebSocket(): Promise<void> {
            console.log('[SimulationStore] Connecting WebSocket...')
            
            await connectWs()
            
            // Register message handlers
            onMessage('frames', (msg) => {
                const frames = (msg.data || []) as SimulationFrame[]
                console.log(`[SimulationStore] Received ${frames.length} frames`)

                if (!currentResult.value || !isResultLoaded(currentResult.value)) {
                    console.error('[SimulationStore] Trying to accumulate frames into not-loaded result.')
                    return
                }
                accumulateFrames(currentResult.value, frames)
                onFrameBatchUpdate(frames)
            })

            onMessage('frame', (msg) => {
                const frame = (msg.data || {}) as SimulationFrame
                if (!currentResult.value || !isResultLoaded(currentResult.value)) {
                    console.error('[SimulationStore] Trying to accumulate frames into not-loaded result.')
                    return
                }
                accumulateFrames(currentResult.value, [frame])
            })

            onMessage('completed', (msg) => {
                console.log('[SimulationStore] Simulation complete')
                if (currentResult.value) {
                    currentResult.value.status = (msg.status as SimulationStatus) || 'completed'
                }
            })

            onMessage('error', (msg) => {
                console.error('[SimulationStore] Error:', msg.error)
                if (currentResult.value) {
                    currentResult.value.status = 'error'
                }
            })

            onMessage('ws_connected', () => {
                console.log('[SimulationStore] WebSocket confirmed by server')
            })

            console.log('[SimulationStore] WebSocket connected and handlers registered')
        }

        // Frame batch callback for visualizations
        let onFrameBatchCallback: ((batch: SimulationFrame[]) => void) | null = null

        function onFrameBatchUpdate(frames: SimulationFrame[]) {
            if (onFrameBatchCallback) {
                onFrameBatchCallback(frames)
            }
        }


        async function loadResult(resultId: string): Promise<SimulationResult> {
            const result = await simulationService.loadSimulationResult(resultId)
            currentResult.value = result
            const scheduleStore = useScheduleStore()
            await scheduleStore.loadScheduleBySpec(result.schedule_spec, result.schedule_name)

            return result
        }

        /**
         * Run simulation for the active schedule
         */
        async function runSimulation(): Promise<SimulationResult> {
            const scheduleStore = useScheduleStore()

            if (!scheduleStore.schedule) {
                throw new Error('No running schedule selected')
            }

            if (!wsConnected.value) {
                throw new Error('WebSocket not connected')
            }

            if (isSimulationRunning.value) {
                throw new Error('Simulation already running')
            }

            currentResult.value = null

            const metadata = await simulationService.runSimulation(scheduleStore.schedule.name, scheduleStore.schedule.spec)

            currentResult.value = {
                ...metadata,
                data: {
                    frames: []
                }
            } as SimulationResult

            return currentResult.value
        }


        /**
         * Register callback for when frame batches arrive
         * Used by visualization components to react to new data
         */
        function onFrameBatch(callback: (batch: SimulationFrame[]) => void) {
            onFrameBatchCallback = callback
        }

        /**
         * Unregister frame batch callback
         */
        function offFrameBatch() {
            onFrameBatchCallback = null
        }


        /**
         * Reset all state
         */
        function reset() {
            currentResult.value = null
            onFrameBatchCallback = null
        }


        return {
            // State
            wsConnected,
            isSimulationRunning,
            currentResult,
            currentResultId,

            // Computed
            currentTimeseries,
            currentResultLabel,

            // WebSocket
            connectWebSocket,

            // Frame callbacks
            onFrameBatch,
            offFrameBatch,

            // API
            runSimulation,
            loadResult,

            // Cleanup
            reset
        }
    }
)
