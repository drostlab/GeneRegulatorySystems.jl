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

    /** Arrange species/reactions in a tight grid inside their parent gene node. */
    private positionCompoundChildren(): void {
        const cy = this.cy!

        cy.nodes('.gene').forEach((gene: any) => {
            const children = gene.children()
            if (children.empty()) return

            const center = gene.position()
            const n = children.length
            const cols = Math.ceil(Math.sqrt(n))
            const rows = Math.ceil(n / cols)
            const spacing = 12
            const startX = center.x - ((cols - 1) * spacing) / 2
            const startY = center.y - ((rows - 1) * spacing) / 2

            children.forEach((child: any, i: number) => {
                const col = i % cols
                const row = Math.floor(i / cols)
                child.position({
                    x: startX + col * spacing,
                    y: startY + row * spacing,
                })
            })
        })
    }
}
