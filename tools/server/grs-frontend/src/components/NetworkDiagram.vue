<script setup lang="ts">
/**
 * NetworkDiagram Component
 *
 * Displays the gene regulatory network from the first segment of the running schedule.
 * Uses Cytoscape with fcose layout for interactive hierarchical graph visualization.
 * Genes are compound nodes containing their reactions and species.
 */
import { ref, onMounted, watch, onBeforeUnmount } from 'vue'
import { useScheduleStore } from '@/stores/scheduleStore'
import { useViewerStore } from '@/stores/viewerStore'
import { convertToElements, getDefaultStyles, getDefaultLayout } from '@/composables/useCytoscapeRenderer'
import cytoscape from 'cytoscape'
// @ts-ignore - cytoscape-fcose doesn't have types
import fcose from 'cytoscape-fcose'
// @ts-ignore - cytoscape-cola doesn't have types
import cola from 'cytoscape-cola'
import type { Network } from '@/types/network'

cytoscape.use(fcose)
cytoscape.use(cola)

const containerRef = ref<HTMLDivElement>()
const store = useScheduleStore()
const viewerStore = useViewerStore()
let cy: cytoscape.Core | null = null
let updateStylesTimeout: ReturnType<typeof setTimeout> | null = null
let fitZoomTimeout: ReturnType<typeof setTimeout> | null = null

/**
 * Blend between two colors based on a factor (0-1)
 * factor 0 = color1, factor 1 = color2
 */
function blendColors(color1: string, color2: string, factor: number): string {
    const hex = (c: string) => {
        const result = c.replace('#', '')
        return {
            r: parseInt(result.substring(0, 2), 16),
            g: parseInt(result.substring(2, 4), 16),
            b: parseInt(result.substring(4, 6), 16)
        }
    }
    
    const c1 = hex(color1)
    const c2 = hex(color2)
    
    const r = Math.round(c1.r + (c2.r - c1.r) * factor)
    const g = Math.round(c1.g + (c2.g - c1.g) * factor)
    const b = Math.round(c1.b + (c2.b - c1.b) * factor)
    
    return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`
}

/**
 * Convert hex color to HSL
 */
function hexToHSL(hex: string): { h: number; s: number; l: number } {
    let r = parseInt(hex.slice(1, 3), 16) / 255
    let g = parseInt(hex.slice(3, 5), 16) / 255
    let b = parseInt(hex.slice(5, 7), 16) / 255
    
    const max = Math.max(r, g, b)
    const min = Math.min(r, g, b)
    const l = (max + min) / 2
    
    if (max === min) {
        return { h: 0, s: 0, l }
    }
    
    const d = max - min
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    
    let h = 0
    switch (max) {
        case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break
        case g: h = ((b - r) / d + 2) / 6; break
        case b: h = ((r - g) / d + 4) / 6; break
    }
    
    return { h, s, l }
}

/**
 * Convert HSL to hex color
 */
function hslToHex(h: number, s: number, l: number): string {
    const c = (1 - Math.abs(2 * l - 1)) * s
    const x = c * (1 - Math.abs((h * 6) % 2 - 1))
    const m = l - c / 2
    
    let r = 0, g = 0, b = 0
    if (h < 1/6) { r = c; g = x; b = 0 }
    else if (h < 2/6) { r = x; g = c; b = 0 }
    else if (h < 3/6) { r = 0; g = c; b = x }
    else if (h < 4/6) { r = 0; g = x; b = c }
    else if (h < 5/6) { r = x; g = 0; b = c }
    else { r = c; g = 0; b = x }
    
    const toHex = (val: number) => Math.round((val + m) * 255).toString(16).padStart(2, '0')
    return `#${toHex(r)}${toHex(g)}${toHex(b)}`
}

/**
 * Render network from first segment
 */
function renderNetwork() {
    if (!store.isValid || !store.segments.length) {
        console.debug('[NetworkDiagram] No valid schedule or segments to render', {
            isValid: store.isValid,
            segmentCount: store.segments.length
        })
        return
    }
    
    const firstSegment = store.segments[0]
    if (!firstSegment?.network) {
        console.debug('[NetworkDiagram] First segment has no network')
        return
    }
    
    const network: Network = firstSegment.network
    
    console.debug('[NetworkDiagram] Rendering network:', { 
        numNodes: network.nodes.length,
        numEdges: network.edges.length
    })
    
    const elements = convertToElements(network, store.geneColours || {})
    
    console.debug('[NetworkDiagram] Generated Cytoscape elements:', { 
        total: elements.length,
        nodes: elements.filter((e: any) => !e.data.source).length,
        edges: elements.filter((e: any) => e.data.source).length
    })
    
    if (!containerRef.value) {
        console.warn('Container ref not available')
        return
    }
    
    cy = cytoscape({
        container: containerRef.value,
        elements,
        wheelSensitivity: 0.1,
        style: getDefaultStyles(),
        layout: getDefaultLayout(),
        userPanningEnabled: true,
        userZoomingEnabled: true,
        boxSelectionEnabled: true,
        selectionType: 'single'
    } as any)
    
    // Add grid background to container
    if (containerRef.value) {
        containerRef.value.style.backgroundImage = 'radial-gradient(circle, #d0d0d0 1.0px, transparent 1.0px)'
        containerRef.value.style.backgroundSize = '30px 30px'
        containerRef.value.style.backgroundPosition = '0 0'
        // Make sure Cytoscape canvas is transparent so grid shows through
        const canvas = containerRef.value.querySelector('canvas') as HTMLCanvasElement
        if (canvas) {
            canvas.style.backgroundColor = 'transparent'
        }
    }
    
    // Fit and zoom out smoothly after layout animation completes
    fitZoomTimeout = setTimeout(() => {
        if (cy && cy.nodes().length > 0) {
            cy.fit(undefined, 100)  // 100px padding
            cy.zoom(0.5)
        }
    }, 1000)
    
    console.debug('[NetworkDiagram] Cytoscape instance created and rendered')
}

/**
 * Update node styles based on species expression levels at current timepoint
 */
function updateNodeStyles() {
    if (!cy) return
    
    // Get timepoint data
    const currentValues = viewerStore.speciesValuesAtTimepoint || {}
    const maxValues = viewerStore.maxValues || {}
    
    try {
        cy.nodes().forEach((node: any) => {
            const nodeId = node.id()
            const nodeKind = node.data('kind')
            
            // Use node.id directly as FlatState key
            const value = currentValues[nodeId] ?? 0
            const maxValue = maxValues[nodeId] ?? 1
            
            if (nodeKind === 'species') {
                // Scale opacity and size based on expression level
                const normalizedValue = Math.min(1, value / maxValue)
                const baseColour = node.data('colour') || '#999999'
                
                // Blend to full saturation at max expression
                const blendedColour = blendColors('#FFFFFF', baseColour, normalizedValue)
                
                node.style({
                    'background-color': blendedColour,
                    'opacity': 0.4 + (0.6 * normalizedValue)
                })
            }                const kind = nodeId.includes('_mrna') ? 'mrnas' : 'proteins'
                const speciesId = `${geneNum}.${kind}`
                const rawValue = viewerStore.speciesValuesAtTimepoint[speciesId] ?? 0
                const maxForAllGenes = kind === 'mrnas' ? globalMaxValues.mrna : globalMaxValues.protein
                
                // Scale relative to global max of same node type (all genes) - more dramatic range
                const relativeValue = rawValue / maxForAllGenes
                const scale = 0.2 + (relativeValue * 4.8)  // 0.2x to 5.0x
                
                if (geneNum === '1' || geneNum === '4') {
                    console.debug(`[Style ${nodeId}] kind=${kind}, speciesId=${speciesId}, rawValue=${rawValue?.toFixed(4)}, maxForAllGenes=${maxForAllGenes.toFixed(4)}, relativeValue=${(rawValue / maxForAllGenes).toFixed(4)}, scale=${scale.toFixed(4)}`)
                }
                
                // Base sizes
                const baseWidth = 50
                const baseHeight = 50
                const maxWidth = 150
                const maxHeight = 150
                
                const width = baseWidth * scale
                const height = baseHeight * scale
                
                // Get original color and modulate saturation based on expression
                const originalColor = node.data('colour') || '#999999'
                const relativeExpr = rawValue / maxForAllGenes
                
                // For saturation, use per-gene max so each gene reaches full saturation at its peak
                const perGeneMax = viewerStore.maxValues[speciesId] ?? 1
                const saturationFactor = Math.min(1, rawValue / perGeneMax)
                
                // Convert to HSL, saturation linear with per-gene expression (0-100%)
                const hsl = hexToHSL(originalColor)
                const saturatedColor = hslToHex(hsl.h, saturationFactor, hsl.l)
                
                if (geneNum === '1' || geneNum === '4') {
                    console.debug(`[Color ${nodeId}] relativeExpr=${relativeExpr?.toFixed(4)}, saturationFactor=${saturationFactor?.toFixed(4)}, saturatedColor=${saturatedColor}`)
                }
                
                node.style({
                    'width': Math.min(width, maxWidth),
                    'height': Math.min(height, maxHeight),
                    'background-color': saturatedColor
                })
            }
        }
        })
        
        // Update edge widths based on protein content - only for gene-to-gene regulatory edges
        cy.edges().forEach((edge: any) => {
            const source = edge.source().id()
            const target = edge.target().id()
            
            // Only scale gene-to-gene regulatory edges (both source and target are gene nodes)
            if (source.startsWith('gene_') && target.startsWith('gene_')) {
                // Extract gene number from source gene node (e.g., 'gene_1' -> '1')
                const sourceGeneNum = source.match(/gene_(\d+)/)?.[1]
                
                if (sourceGeneNum) {
                    // Get protein expression for source gene
                    const sourceProtein = viewerStore.speciesValuesAtTimepoint[`${sourceGeneNum}.proteins`] ?? 0
                    
                    // Scale edge width relative to global max protein
                    const maxProtein = globalMaxValues.protein
                    const edgeWidth = 2 + (sourceProtein / maxProtein) * 12  // 2 to 14
                    
                    edge.style({
                        'width': edgeWidth
                    })
                }
            }
        })
    } catch (err) {
        console.debug('Error updating node styles or edges:', err)
    }
}

onMounted(() => {
    console.debug('[NetworkDiagram] Component mounted', {
        scheduleValid: store.isValid,
        segmentCount: store.segments.length
    })
    renderNetwork()
})

onBeforeUnmount(() => {
    if (updateStylesTimeout) {
        clearTimeout(updateStylesTimeout)
    }
    if (fitZoomTimeout) {
        clearTimeout(fitZoomTimeout)
    }
    if (cy) {
        cy.destroy()
        cy = null
    }
})

// Watch for schedule changes
watch(
    () => store.schedule,
    () => {
        console.debug('[NetworkDiagram] Schedule changed, re-rendering network', {
            scheduleValid: store.isValid,
            segmentCount: store.segments.length
        })
        // Clear pending timeouts and destroy old instance before creating new one
        if (fitZoomTimeout) {
            clearTimeout(fitZoomTimeout)
            fitZoomTimeout = null
        }
        if (cy) {
            cy.destroy()
            cy = null
        }
        renderNetwork()
    },
    { deep: true }
)

// Watch for timepoint changes from trajectory viewer
watch(
    () => viewerStore.currentTimepoint,
    (newTimepoint, oldTimepoint) => {
        console.debug('Timepoint changed in viewer', {
            oldTimepoint,
            newTimepoint,
            hasCy: cy !== null,
            timeseries: viewerStore.timeseries !== null
        })
        // Use setTimeout to debounce rapid timepoint updates
        clearTimeout(updateStylesTimeout)
        updateStylesTimeout = setTimeout(() => {
            updateNodeStyles()
        }, 16)  // ~60fps
    }
)
</script>

<template>
    <div class="network-diagram-container">
        <div ref="containerRef" class="cytoscape-container"></div>
        <div
            v-if="store.isLoading"
            class="loading-overlay"
        >
            <div style="text-align: center">
                <div style="font-size: 18px; color: #333; margin-bottom: 16px">Loading schedule...</div>
                <div class="spinner"></div>
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
