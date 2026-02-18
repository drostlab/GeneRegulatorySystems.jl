<script setup lang="ts">
import Splitter from 'primevue/splitter'
import SplitterPanel from 'primevue/splitterpanel'
import Button from 'primevue/button'
import ScheduleEditor from './components/ScheduleEditor.vue'
import NetworkDiagram from './components/NetworkDiagram.vue'
import SimulationViewer from './components/TrackViewer.vue'
import { useTheme } from './composables/useTheme'

const { isDark, toggle } = useTheme()
</script>

<template>
    <div style="display: flex; flex-direction: column; width: 100vw; height: 100vh">
        <Button
            :icon="isDark ? 'pi pi-moon' : 'pi pi-sun'"
            severity="secondary"
            text
            rounded
            aria-label="Toggle dark mode"
            class="theme-toggle"
            @click="toggle"
        />
        <!-- Main 3-panel layout with horizontal splitter -->
        <Splitter layout="horizontal" style="flex: 1; overflow: hidden">
            <SplitterPanel style="display: flex; flex-direction: column" :size="30" :minSize="15">
                <ScheduleEditor />
            </SplitterPanel>

            <SplitterPanel style="display: flex; flex-direction: column" :size="70" :minSize="50">
                <Splitter layout="vertical" style="height: 100%; width: 100%">
                    <SplitterPanel style="display: flex; width: 100%" :size="45" :minSize="20">
                        <NetworkDiagram />
                    </SplitterPanel>
                        
                    
                    <SplitterPanel style="display: flex; width: 100%" :size="55" :minSize="20">
                        <SimulationViewer />
                    </SplitterPanel>
                </Splitter>
            </SplitterPanel>
        </Splitter>
    </div>
</template>

<style scoped>
.theme-toggle {
    position: fixed;
    top: 0.5rem;
    right: 0.5rem;
    z-index: 1000;
}
</style>