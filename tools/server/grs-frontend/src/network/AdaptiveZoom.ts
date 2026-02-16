/**
 * Adaptive zoom: shows/hides species and reaction nodes based on zoom level.
 *
 * Below the threshold, only gene nodes (and orphan species) are visible.
 * Above, species + reactions are added as compound children of gene nodes,
 * positioned in a circle inside their parent gene.
 *
 * Saves and restores gene positions to prevent layout shifts on toggle.
 */
import type { Core, EventHandler } from 'cytoscape'
import type { UnionNetwork } from '@/types/network'
import { getDetailElements } from './networkElements'
import { SPECIES_TYPES } from '@/types/schedule'

/** Zoom level above which species/reactions become visible. */
const ZOOM_THRESHOLD = 3.0

/** Reduced debounce for responsive zoom interaction. */
const DEBOUNCE_MS = 50

export class AdaptiveZoom {
    private cy: Core | null = null
    private network: UnionNetwork | null = null
    private geneColours: Record<string, string> = {}
    private detailVisible = false
    private timeout: ReturnType<typeof setTimeout> | null = null
    private handler: EventHandler | null = null

    /** Callback fired when detail visibility changes (for external modules to refresh). */
    onDetailChange: ((visible: boolean) => void) | null = null

    attach(cy: Core, network: UnionNetwork, geneColours: Record<string, string>): void {
        this.cy = cy
        this.network = network
        this.geneColours = geneColours
        this.detailVisible = false

        this.handler = () => this.scheduleCheck()
        cy.on('zoom', this.handler)
    }

    destroy(): void {
        if (this.timeout) {
            clearTimeout(this.timeout)
            this.timeout = null
        }
        if (this.cy && this.handler) {
            this.cy.off('zoom', this.handler)
        }
        this.handler = null
        this.cy = null
        this.network = null
    }

    get isDetailVisible(): boolean {
        return this.detailVisible
    }

    private scheduleCheck(): void {
        if (this.timeout) clearTimeout(this.timeout)
        this.timeout = setTimeout(() => this.checkZoom(), DEBOUNCE_MS)
    }

    private checkZoom(): void {
        const cy = this.cy
        if (!cy || !this.network) return

        const shouldShow = cy.zoom() > ZOOM_THRESHOLD
        if (shouldShow === this.detailVisible) return

        if (shouldShow) {
            this.showDetail()
        } else {
            this.hideDetail()
        }
    }

    private showDetail(): void {
        const cy = this.cy!
        const elements = getDetailElements(this.network!, this.geneColours)
        if (elements.length === 0) return

        // Save gene positions before adding children (which changes compound layout)
        const genePositions = this.saveGenePositions()

        // Filter out elements already present in graph
        const existing = new Set(cy.elements().map((e: any) => e.id()))
        const newElements = elements.filter(e => !existing.has(e.data.id as string))
        if (newElements.length === 0) return

        cy.startBatch()
        cy.add(newElements)

        // Restore gene positions (compound parent auto-sizing may have shifted them)
        this.restoreGenePositions(genePositions)

        // Position children inside their gene parents
        this.positionCompoundChildren()

        cy.endBatch()

        this.detailVisible = true
        this.onDetailChange?.(true)
        console.debug(`[AdaptiveZoom] Detail shown: ${newElements.length} elements added`)
    }

    private hideDetail(): void {
        const cy = this.cy!

        // Save gene positions before removing children
        const genePositions = this.saveGenePositions()

        cy.startBatch()
        cy.nodes('.species, .reaction').remove()

        // Restore gene positions
        this.restoreGenePositions(genePositions)
        cy.endBatch()

        this.detailVisible = false
        this.onDetailChange?.(false)
        console.debug('[AdaptiveZoom] Detail hidden')
    }

    /** Save all gene/orphan-species positions. */
    private saveGenePositions(): Map<string, { x: number; y: number }> {
        const positions = new Map<string, { x: number; y: number }>()
        this.cy!.nodes('.gene, .orphan-species').forEach((n: any) => {
            const pos = n.position()
            positions.set(n.id(), { x: pos.x, y: pos.y })
        })
        return positions
    }

    /** Restore saved gene/orphan-species positions. */
    private restoreGenePositions(positions: Map<string, { x: number; y: number }>): void {
        positions.forEach((pos, id) => {
            const node = this.cy!.getElementById(id)
            if (!node.empty()) {
                node.position(pos)
            }
        })
    }

    /**
     * Position compound children inside their gene parents.
     * Species nodes get hardcoded positions following the cascade:
     *   active -> elongations -> premrnas -> mrnas -> proteins
     * Reaction nodes are placed at the centroid of their connected species.
     */
    private positionCompoundChildren(): void {
        const cy = this.cy!

        // Hardcoded relative offsets for each species type in a zig-zag cascade
        const speciesOffsets: Record<string, { x: number; y: number }> = {
            active:      { x: -30, y: -15 },
            elongations: { x: -15, y:  15 },
            premrnas:    { x:   0, y: -15 },
            mrnas:       { x:  15, y:  15 },
            proteins:    { x:  30, y: -15 },
        }

        cy.nodes('.gene').forEach((gene: any) => {
            const children = gene.children()
            if (children.empty()) return

            const center = gene.position()

            // First pass: position species nodes
            children.forEach((child: any) => {
                if (child.data('kind') !== 'species') return
                const speciesType = child.data('species_type') as string | undefined
                const offset = speciesOffsets[speciesType ?? '']
                if (offset) {
                    child.position({
                        x: center.x + offset.x,
                        y: center.y + offset.y,
                    })
                }
            })

            // Second pass: position reaction nodes at centroid of connected neighbours
            children.forEach((child: any) => {
                if (child.data('kind') !== 'reaction') return
                const pos = computeNeighbourCentroid(child, center)
                child.position(pos)
            })
        })
    }
}

/**
 * Compute the centroid of a node's connected neighbours.
 * Falls back to the parent centre if no positioned neighbours are found.
 * For single-neighbour reactions, offsets perpendicular to avoid overlap.
 */
function computeNeighbourCentroid(
    node: any,
    fallback: { x: number; y: number },
): { x: number; y: number } {
    const neighbours = node.neighborhood('node')
    if (neighbours.empty()) return { x: fallback.x, y: fallback.y + 15 }

    let sumX = 0
    let sumY = 0
    let count = 0

    neighbours.forEach((n: any) => {
        const pos = n.position()
        sumX += pos.x
        sumY += pos.y
        count++
    })

    if (count === 0) return { x: fallback.x, y: fallback.y + 15 }

    const cx = sumX / count
    const cy = sumY / count

    // Single neighbour: offset away from it so the reaction isn't on top of the species
    if (count === 1) {
        const nPos = neighbours.first().position()
        const dx = cx - fallback.x
        const dy = cy - fallback.y
        const dist = Math.sqrt(dx * dx + dy * dy)
        if (dist > 0.1) {
            // Place perpendicular to the direction from centre to neighbour
            return { x: cx - (dy / dist) * 20, y: cy + (dx / dist) * 20 }
        }
        return { x: cx + 10, y: cy }
    }

    return { x: cx, y: cy }
}
