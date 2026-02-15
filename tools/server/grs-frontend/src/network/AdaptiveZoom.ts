/**
 * Adaptive zoom: shows/hides species and reaction nodes based on zoom level.
 *
 * Below the threshold, only gene nodes (and orphan species) are visible.
 * Above, species + reactions are added with a secondary layout that pins
 * existing gene positions.
 *
 * Uses cy.add/remove instead of opacity for performance on large networks.
 */
import type { Core, EventHandler } from 'cytoscape'
import type { UnionNetwork } from '@/types/network'
import { getDetailElements } from './networkElements'
import { buildStylesheet } from './networkStyles'

/** Zoom level above which species/reactions become visible. */
const ZOOM_THRESHOLD = 0.6

const DEBOUNCE_MS = 150

export class AdaptiveZoom {
    private cy: Core | null = null
    private network: UnionNetwork | null = null
    private geneColours: Record<string, string> = {}
    private detailVisible = false
    private timeout: ReturnType<typeof setTimeout> | null = null
    private handler: EventHandler | null = null

    /** Callbacks fired when detail visibility changes (for external modules to refresh). */
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

        const zoom = cy.zoom()
        const shouldShow = zoom > ZOOM_THRESHOLD

        if (shouldShow === this.detailVisible) return

        if (shouldShow) {
            this.showDetailNodes()
        } else {
            this.hideDetailNodes()
        }
    }

    private showDetailNodes(): void {
        const cy = this.cy!
        const network = this.network!

        const elements = getDetailElements(network, this.geneColours)
        if (elements.length === 0) return

        cy.startBatch()

        // Update stylesheet for species-visible mode (gene labels above)
        cy.style().fromJson(buildStylesheet(true)).update()

        // Add detail elements
        cy.add(elements)

        cy.endBatch()

        // Run secondary layout with gene nodes pinned
        const geneNodes = cy.nodes('.gene, .orphan-species')
        const fixedConstraints = geneNodes.map((n: any) => ({
            nodeId: n.id(),
            position: n.position(),
        }))

        const detailNodes = cy.nodes('.species, .reaction')
        if (detailNodes.length > 0) {
            cy.layout({
                name: 'fcose',
                quality: 'default',
                randomize: false,
                animate: true,
                animationDuration: 500,
                fit: false,
                fixedNodeConstraint: fixedConstraints,
                nodeRepulsion: 3000,
                idealEdgeLength: 60,
                edgeElasticity: 0.3,
                numIter: 1000,
            } as any).run()
        }

        this.detailVisible = true
        this.onDetailChange?.(true)
        console.debug(`[AdaptiveZoom] Detail nodes shown: ${elements.length} elements`)
    }

    private hideDetailNodes(): void {
        const cy = this.cy!

        cy.startBatch()

        // Update stylesheet for gene-only mode (labels inside)
        cy.style().fromJson(buildStylesheet(false)).update()

        // Remove species + reaction nodes (and their connected edges)
        const detailNodes = cy.nodes('.species, .reaction')
        detailNodes.connectedEdges().remove()
        detailNodes.remove()

        cy.endBatch()

        this.detailVisible = false
        this.onDetailChange?.(false)
        console.debug('[AdaptiveZoom] Detail nodes hidden')
    }
}
