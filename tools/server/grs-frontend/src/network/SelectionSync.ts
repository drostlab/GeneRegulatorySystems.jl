/**
 * Two-way selection sync between viewerStore.selectedGenes and cytoscape.
 *
 * - viewerStore.selectedGenes changes -> highlight matching gene nodes, dim others.
 * - User taps a gene node in cytoscape -> update viewerStore.selectedGenes.
 * - Reentrancy guard prevents infinite loops.
 * - When species are visible, only highlights species whose gene is selected.
 */
import type { Core } from 'cytoscape'
import { watch, type WatchStopHandle } from 'vue'
import { useViewerStore } from '@/stores/viewerStore'

export class SelectionSync {
    private cy: Core | null = null
    private stopWatch: WatchStopHandle | null = null
    private updating = false

    attach(cy: Core): void {
        this.cy = cy

        // Cytoscape -> store
        cy.on('tap', 'node.gene, node.orphan-species', this.onNodeTap)

        // Store -> cytoscape
        this.stopWatch = watch(
            () => useViewerStore().selectedGenes,
            () => this.syncFromStore(),
            { immediate: true, deep: true },
        )
    }

    destroy(): void {
        this.stopWatch?.()
        this.stopWatch = null
        if (this.cy) {
            this.cy.off('tap', 'node.gene, node.orphan-species', this.onNodeTap)
        }
        this.cy = null
    }

    /** Re-apply highlighting after elements change. */
    refresh(): void {
        this.syncFromStore()
    }

    // ========================================================================
    // Cytoscape -> Store
    // ========================================================================

    private onNodeTap = (evt: any): void => {
        if (this.updating) return
        this.updating = true

        const node = evt.target
        const viewerStore = useViewerStore()
        const geneId = node.data('kind') === 'gene'
            ? node.id()
            : node.data('geneParent') ?? node.id()

        const currentSelection = viewerStore.selectedGenes
        if (currentSelection.length === 1 && currentSelection[0] === geneId) {
            // Deselect: restore all genes
            viewerStore.selectedGenes = []
        } else {
            viewerStore.selectedGenes = [geneId]
        }

        this.updating = false
    }

    // ========================================================================
    // Store -> Cytoscape
    // ========================================================================

    private syncFromStore(): void {
        if (this.updating || !this.cy) return
        this.updating = true

        const cy = this.cy
        const viewerStore = useViewerStore()
        const selectedGenes = viewerStore.selectedGenes

        cy.startBatch()

        if (selectedGenes.length === 0) {
            // No selection: remove all highlighting/dimming
            cy.elements().removeClass('dimmed highlighted')
        } else {
            const selectedSet = new Set(selectedGenes)

            cy.nodes().forEach((node: any) => {
                const kind = node.data('kind')
                const geneId = kind === 'gene'
                    ? node.id()
                    : node.data('geneParent') ?? null

                const isSelected = geneId !== null && selectedSet.has(geneId)
                node.toggleClass('highlighted', isSelected && kind === 'gene')
                node.toggleClass('dimmed', !isSelected)
            })

            cy.edges().forEach((edge: any) => {
                const sourceGene = resolveGene(cy, edge.data('source'))
                const targetGene = resolveGene(cy, edge.data('target'))
                const isConnected = (sourceGene !== null && selectedSet.has(sourceGene))
                    || (targetGene !== null && selectedSet.has(targetGene))
                edge.toggleClass('dimmed', !isConnected)
            })
        }

        cy.endBatch()
        this.updating = false
    }
}

/** Resolve a node ID to its gene (either itself if gene, or its geneParent). */
function resolveGene(cy: Core, nodeId: string): string | null {
    const node = cy.getElementById(nodeId)
    if (node.empty()) return null
    return node.data('kind') === 'gene'
        ? nodeId
        : node.data('geneParent') ?? null
}
