<script setup lang="ts">
import { ref, onMounted, watch, onBeforeUnmount, computed } from 'vue'
import { useScheduleStore } from '@/stores/scheduleStore'
import { useViewerStore } from '@/stores/viewerStore'
import { NetworkView } from '@/network/NetworkView'
import ProgressSpinner from 'primevue/progressspinner'

const containerRef = ref<HTMLDivElement>()
const scheduleStore = useScheduleStore()
const viewerStore = useViewerStore()
const networkView = new NetworkView()

/** Label for the active model shown in the bottom-left overlay. */
const activeModelLabel = computed(() => {
    const modelPath = viewerStore.activeModelPath
    if (!modelPath) return null

    const segments = scheduleStore.segments
    const seg = segments.find(s => s.model_path === modelPath && s.from !== s.to)
    return {
        label: seg?.label ?? modelPath,
        path: modelPath,
    }
})

onMounted(() => {
    networkView.init(containerRef)

    // Render when union network arrives
    if (scheduleStore.unionNetwork) {
        networkView.setNetwork(scheduleStore.unionNetwork, scheduleStore.geneColours ?? {})
    }
})

onBeforeUnmount(() => {
    networkView.destroy()
})

watch(() => scheduleStore.unionNetwork, (network) => {
    if (network) {
        networkView.setNetwork(network, scheduleStore.geneColours ?? {})
    }
})
</script>

<template>
    <div class="network-diagram-container">
        <div ref="containerRef" class="cytoscape-container" />

        <!-- Model info overlay -->
        <div v-if="activeModelLabel" class="model-label-overlay">
            <div class="model-label-name">{{ activeModelLabel.label }}</div>
            <div class="model-label-path">{{ activeModelLabel.path }}</div>
        </div>

        <div v-if="scheduleStore.isLoading" class="loading-overlay">
            <div class="loading-card">
                <ProgressSpinner style="width: 50px; height: 50px" stroke-width="3" />
                <div class="loading-text">Loading network...</div>
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

.model-label-overlay {
    position: absolute;
    bottom: 8px;
    left: 8px;
    background: rgba(255, 255, 255, 0.85);
    border-radius: 4px;
    padding: 4px 8px;
    font-family: Montserrat, sans-serif;
    pointer-events: none;
    max-width: 60%;
}

.model-label-name {
    font-size: 12px;
    font-weight: 600;
    color: #333;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.model-label-path {
    font-size: 10px;
    color: #777;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.network-diagram-container :deep(.loading-card) {
    margin-top: 80px;
}
</style>
