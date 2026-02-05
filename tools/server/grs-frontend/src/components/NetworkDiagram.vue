<script setup lang="ts">
/**
 * NetworkDiagram
 * Displays gene regulatory network with dynamic expression-driven styling
 */
import { ref, onMounted, watch, onBeforeUnmount } from 'vue'
import { useScheduleStore } from '@/stores/scheduleStore'
import { convertToElements, getDefaultStyles, getDefaultLayout } from '@/composables/useCytoscapeRenderer'
import { useNetworkDynamics } from '@/composables/useNetworkDynamics'
import { useAdaptiveZoom } from '@/composables/useAdaptiveZoom'
import cytoscape from 'cytoscape'
// @ts-ignore
import fcose from 'cytoscape-fcose'

cytoscape.use(fcose)

const containerRef = ref<HTMLDivElement>()
const cy = ref<cytoscape.Core | null>(null)
const store = useScheduleStore()

useNetworkDynamics(cy)

let cleanupAdaptiveZoom: (() => void) | null = null

let fitZoomTimeout: ReturnType<typeof setTimeout> | null = null

function renderNetwork() {
    const startTime = performance.now()
    console.debug('Starting network render')
    
    if (!store.isValid || !store.schedule.data) return

    const network = store.schedule.data.network
    if (!network) return

    console.debug(`Network has ${network.nodes.length} nodes, ${network.links.length} links`)
    
    const elementsStart = performance.now()
    const elements = convertToElements(network, store.geneColours || {})
    console.debug(`Element conversion took ${(performance.now() - elementsStart).toFixed(2)}ms`)

    if (!containerRef.value) return

    const cyStart = performance.now()
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
    })
    console.debug(`Cytoscape init took ${(performance.now() - cyStart).toFixed(2)}ms`)

    // Grid background
    if (containerRef.value) {
        containerRef.value.style.backgroundImage = 
            'radial-gradient(circle, #d0d0d0 1px, transparent 1px)'
        containerRef.value.style.backgroundSize = '30px 30px'
    }

    console.debug('Layout will complete in 1000ms, then applying fit/zoom')
    
    // Fit viewport after layout
    fitZoomTimeout = setTimeout(() => {
        const layoutCompleteTime = performance.now()
        console.debug('Layout complete, applying fit and zoom')
        
        if (cy.value && cy.value.nodes().length > 0) {
            cy.value.fit(undefined, 100)
            cy.value.zoom(0.5)
            
            const adaptiveStart = performance.now()
            cleanupAdaptiveZoom = useAdaptiveZoom(cy.value)
            console.debug(`Adaptive zoom setup took ${(performance.now() - adaptiveStart).toFixed(2)}ms`)
        }
        
        console.debug(`Total render time: ${(performance.now() - startTime).toFixed(2)}ms`)
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

// Trigger render only when loading finishes, not during loading
watch(() => store.isLoading, (isLoading) => {
    if (!isLoading) {
        destroyNetwork()
        renderNetwork()
    } else {
        destroyNetwork()
    }
})
</script>

<template>
    <div class="network-diagram-container">
        <div ref="containerRef" class="cytoscape-container" />
        <div v-if="store.isLoading" class="loading-overlay">
            <div class="loading-content">
                <div class="loading-text">Loading schedule...</div>
                <div class="spinner" />
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

.loading-overlay {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: rgba(255, 255, 255, 0.9);
    z-index: 10;
}

.loading-content {
    text-align: center;
}

.loading-text {
    font-size: 18px;
    color: #333;
    margin-bottom: 16px;
}

.spinner {
    display: inline-block;
    width: 40px;
    height: 40px;
    border: 4px solid #e0e0e0;
    border-top-color: #333;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
}

@keyframes spin {
    to {
        transform: rotate(360deg);
    }
}
</style>
