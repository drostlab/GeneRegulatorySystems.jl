<script setup lang="ts">
import { ref, onMounted, watch, onBeforeUnmount } from 'vue'
import { useScheduleStore } from '@/stores/scheduleStore'
import { convertToElements, getDefaultStyles, getDefaultLayout } from '@/composables/useCytoscapeRenderer'
import { useAdaptiveZoom } from '@/composables/useAdaptiveZoom'
import ProgressSpinner from 'primevue/progressspinner'
import cytoscape from 'cytoscape'
// @ts-ignore
import fcose from 'cytoscape-fcose'

cytoscape.use(fcose)

const containerRef = ref<HTMLDivElement>()
const cy = ref<cytoscape.Core | null>(null)
const store = useScheduleStore()

let cleanupAdaptiveZoom: (() => void) | null = null
let fitZoomTimeout: ReturnType<typeof setTimeout> | null = null

function renderNetwork() {
    const network = store.activeNetwork
    if (!network) return

    console.debug(`[NetworkDiagram] Rendering network: ${network.nodes.length} nodes, ${network.links.length} links`)

    const elements = convertToElements(network, store.geneColours || {})
    if (!containerRef.value) return

    cy.value = cytoscape({
        container: containerRef.value,
        elements,
        wheelSensitivity: 0.1,
        style: getDefaultStyles(),
        layout: getDefaultLayout(),
        renderer: {
            name: 'canvas',
            webgl: true,
            showFps: false,
            webglDebug: false,
            webglTexSize: 4096,
            webglTexRows: 24,
            webglBatchSize: 2048,
            webglTexPerBatch: 16
        },
        userPanningEnabled: true,
        userZoomingEnabled: true,
        boxSelectionEnabled: false,
        selectionType: 'single'
    } as any)

    if (containerRef.value) {
        containerRef.value.style.backgroundImage =
            'radial-gradient(circle, #d0d0d0 1px, transparent 1px)'
        containerRef.value.style.backgroundSize = '30px 30px'
    }

    fitZoomTimeout = setTimeout(() => {
        if (cy.value && cy.value.nodes().length > 0) {
            cy.value.fit(undefined, 100)
            cy.value.zoom(0.5)
            cleanupAdaptiveZoom = useAdaptiveZoom(cy.value)
        }
    }, 1000)
}

function destroyNetwork() {
    if (fitZoomTimeout) {
        clearTimeout(fitZoomTimeout)
        fitZoomTimeout = null
    }
    if (cleanupAdaptiveZoom) {
        cleanupAdaptiveZoom()
        cleanupAdaptiveZoom = null
    }
    if (cy.value) {
        cy.value.destroy()
        cy.value = null
    }
}

onMounted(renderNetwork)
onBeforeUnmount(destroyNetwork)

watch(() => store.activeNetwork, () => {
    destroyNetwork()
    renderNetwork()
})
</script>

<template>
    <div class="network-diagram-container">
        <div ref="containerRef" class="cytoscape-container" />
        <div v-if="store.isLoading" class="loading-overlay">
            <div class="loading-card">
                <ProgressSpinner style="width: 50px; height: 50px" stroke-width="3" />
                <div class="loading-text">Loading schedule...</div>
            </div>
        </div>
    </div>
</template>

<style scoped>
.network-diagram-container {
    width: 100%;
    height: 100%;
    position: relative;
    overflow: hidden;
}

.cytoscape-container {
    width: 100%;
    height: 100%;
    position: absolute;
    inset: 0;
}

.network-diagram-container :deep(.loading-card) {
    margin-top: 80px;
}
</style>
