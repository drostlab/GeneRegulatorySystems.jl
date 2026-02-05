/**
 * Network dynamics composable
 * Handles timepoint-driven node/edge style updates
 */
import { ref, watch, type Ref } from 'vue'
import type { Core } from 'cytoscape'
import { useViewerStore } from '@/stores/viewerStore'
import { lerpColor } from '@/utils/colorUtils'

export function useNetworkDynamics(cy: Ref<Core | null>) {
    const viewerStore = useViewerStore()
    const updateTimeout = ref<ReturnType<typeof setTimeout> | null>(null)

    /**
     * Update node styles based on current timepoint species values
     */
    function updateNodeStyles() {
        if (!cy.value) return

        const values = viewerStore.speciesValuesAtTimepoint
        const maxValues = viewerStore.maxValues

        cy.value.nodes('[kind="species"]').forEach((node: any) => {
            const id = node.id()
            const value = values[id] ?? 0
            const maxValue = maxValues[id] ?? 1
            const normalised = Math.min(1, value / maxValue)

            const baseColour = node.data('colour') || '#999999'
            const colour = lerpColor('#FFFFFF', baseColour, normalised)
            const opacity = 0.4 + 0.6 * normalised

            node.style({
                'background-color': colour,
                'opacity': opacity
            })
        })
    }

    /**
     * Update edge styles based on source node expression
     */
    function updateEdgeStyles() {
        if (!cy.value) return

        const values = viewerStore.speciesValuesAtTimepoint
        const maxValues = viewerStore.maxValues

        cy.value.edges().forEach((edge: any) => {
            const sourceId = edge.source().id()
            const kind = edge.data('kind')

            // Only scale regulatory edges
            if (kind === 'activation' || kind === 'repression') {
                const value = values[sourceId] ?? 0
                const maxValue = maxValues[sourceId] ?? 1
                const normalised = Math.min(1, value / maxValue)

                const width = 2 + normalised * 10  // 2-12px range

                edge.style({ 'width': width })
            }
        })
    }

    /**
     * Apply all dynamic updates
     */
    function applyDynamicUpdates() {
        const startTime = performance.now()
        updateNodeStyles()
        updateEdgeStyles()
        const elapsed = performance.now() - startTime
        console.debug(`Dynamic updates took ${elapsed.toFixed(2)}ms`)
    }

    // Watch for timepoint changes with debouncing
    watch(
        () => viewerStore.currentTimepoint,
        () => {
            if (updateTimeout.value) {
                clearTimeout(updateTimeout.value)
            }
            updateTimeout.value = setTimeout(applyDynamicUpdates, 16)  // ~60fps
        }
    )

    return {
        applyDynamicUpdates,
        updateNodeStyles,
        updateEdgeStyles
    }
}
