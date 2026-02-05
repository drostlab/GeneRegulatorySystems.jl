/**
 * Adaptive zoom composable
 * Handles level-based node/edge visibility with smooth opacity transitions
 * Culls nodes outside viewport for performance
 */
import type { Core, NodeSingular } from 'cytoscape'

interface ZoomThreshold {
    minZoom: number
    maxZoom: number
}

interface LevelConfig {
    level: number
    threshold: ZoomThreshold
}

const LEVEL_CONFIGS: LevelConfig[] = [
    { level: 0, threshold: { minZoom: 0.3, maxZoom: 0.5 } },  // reactions, species
    { level: 1, threshold: { minZoom: 0.15, maxZoom: 0.3 } },  // genes
    { level: 2, threshold: { minZoom: 0, maxZoom: 0 } }  // always visible
]

const UPDATE_DEBOUNCE_MS = 50

/**
 * Get visibility level for a node based on its kind
 * @param kind - Node kind (gene, species, reaction, etc.)
 * @returns Visibility level (0 = hides first, higher = more persistent)
 */
function getNodeLevel(kind: string): number {
    if (kind === 'reaction' || kind === 'species') return 0
    if (kind === 'gene') return 1
    return 2
}

/**
 * Calculate opacity for a given level at current zoom
 * @param level - Visibility level
 * @param zoom - Current zoom level
 * @returns Opacity value 0-1
 */
function calculateOpacity(level: number, zoom: number): number {
    const config = LEVEL_CONFIGS[level]
    if (!config) return 1

    const { minZoom, maxZoom } = config.threshold
    
    if (zoom <= minZoom) return 0
    if (zoom >= maxZoom || maxZoom === 0) return 1
    
    return (zoom - minZoom) / (maxZoom - minZoom)
}

/**
 * Check if node is within viewport bounds with margin
 * @param node - Cytoscape node
 * @param extent - Viewport extent {x1, y1, x2, y2}
 * @param margin - Extra margin in pixels
 * @returns true if node is visible in viewport
 */
function isNodeInViewport(node: NodeSingular, extent: any, margin = 100): boolean {
    const pos = node.position()
    const width = node.width()
    const height = node.height()
    
    return pos.x + width / 2 + margin >= extent.x1 &&
           pos.x - width / 2 - margin <= extent.x2 &&
           pos.y + height / 2 + margin >= extent.y1 &&
           pos.y - height / 2 - margin <= extent.y2
}

/**
 * Set up adaptive zoom behaviour for cytoscape instance
 * @param cy - Cytoscape core instance
 * @returns Cleanup function
 */
export function useAdaptiveZoom(cy: Core) {
    let updateTimeout: ReturnType<typeof setTimeout> | null = null
    
    /**
     * Update visibility of all nodes and edges based on zoom and viewport
     */
    function updateVisibility() {
        // DISABLED: Adaptive network rendering temporarily disabled
        return
        const startTime = performance.now()
        const zoom = cy.zoom()
        const extent = cy.extent()
        
        cy.startBatch()
        
        const nodeOpacities = new Map<string, number>()
        const nodeCount = cy.nodes().length
        const edgeCount = cy.edges().length
        
        cy.nodes().forEach((node: NodeSingular) => {
            const kind = node.data('kind')
            const level = getNodeLevel(kind)
            
            let opacity = calculateOpacity(level, zoom)
            
            if (opacity > 0 && !isNodeInViewport(node, extent)) {
                opacity = 0
            }
            
            node.style('opacity', opacity)
            nodeOpacities.set(node.id(), opacity)
        })
        
        cy.edges().forEach((edge: any) => {
            const sourceId = edge.source().id()
            const targetId = edge.target().id()
            
            const sourceOpacity = nodeOpacities.get(sourceId) ?? 1
            const targetOpacity = nodeOpacities.get(targetId) ?? 1
            
            const edgeOpacity = Math.min(sourceOpacity, targetOpacity)
            
            edge.style('opacity', edgeOpacity)
        })
        
        cy.endBatch()
        
        const elapsed = performance.now() - startTime
        console.debug(`Visibility update: ${nodeCount} nodes, ${edgeCount} edges in ${elapsed.toFixed(2)}ms (zoom: ${zoom.toFixed(2)})`)
    }
    
    /**
     * Debounced visibility update
     */
    function scheduleUpdate() {
        if (updateTimeout) {
            clearTimeout(updateTimeout)
        }
        updateTimeout = setTimeout(updateVisibility, UPDATE_DEBOUNCE_MS)
    }
    
    cy.on('zoom viewport', scheduleUpdate)
    
    updateVisibility()
    
    return function cleanup() {
        if (updateTimeout) {
            clearTimeout(updateTimeout)
        }
        cy.off('zoom viewport', scheduleUpdate)
    }
}
