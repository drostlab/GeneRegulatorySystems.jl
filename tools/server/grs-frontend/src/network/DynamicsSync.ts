/**
 * Dynamic node sizing based on simulation protein counts.
 *
 * Watches viewerStore.proteinCountsAtTimepoint and scales gene node
 * width/height proportionally within GENE_SIZE_RANGE.
 * Debounced at ~60fps.
 */
import type { Core } from 'cytoscape'
import { watch, type WatchStopHandle } from 'vue'
import { useViewerStore } from '@/stores/viewerStore'
import { GENE_BASE, GENE_SIZE_RANGE } from './networkStyles'

const DEBOUNCE_MS = 16

export class DynamicsSync {
    private cy: Core | null = null
    private stopWatch: WatchStopHandle | null = null
    private timeout: ReturnType<typeof setTimeout> | null = null

    attach(cy: Core): void {
        this.cy = cy

        this.stopWatch = watch(
            () => useViewerStore().proteinCountsAtTimepoint,
            () => this.scheduleUpdate(),
            { deep: true },
        )
    }

    destroy(): void {
        this.stopWatch?.()
        this.stopWatch = null
        if (this.timeout) {
            clearTimeout(this.timeout)
            this.timeout = null
        }
        this.cy = null
    }

    /** Reset all gene nodes to base size. */
    resetSizes(): void {
        if (!this.cy) return
        this.cy.startBatch()
        this.cy.nodes('.gene').forEach((node: any) => {
            node.style({ width: GENE_BASE.width, height: GENE_BASE.height })
        })
        this.cy.endBatch()
    }

    private scheduleUpdate(): void {
        if (this.timeout) clearTimeout(this.timeout)
        this.timeout = setTimeout(() => this.applyDynamicSizing(), DEBOUNCE_MS)
    }

    private applyDynamicSizing(): void {
        const cy = this.cy
        if (!cy) return

        const viewerStore = useViewerStore()
        const counts = viewerStore.proteinCountsAtTimepoint
        const maxCounts = viewerStore.maxProteinCounts

        if (Object.keys(counts).length === 0) return

        cy.startBatch()
        cy.nodes('.gene').forEach((node: any) => {
            const gene = node.id()
            const value = counts[gene] ?? 0
            const maxValue = maxCounts[gene] ?? 1
            const normalised = maxValue > 0 ? Math.min(1, value / maxValue) : 0

            const w = GENE_SIZE_RANGE.minW + normalised * (GENE_SIZE_RANGE.maxW - GENE_SIZE_RANGE.minW)
            const h = GENE_SIZE_RANGE.minH + normalised * (GENE_SIZE_RANGE.maxH - GENE_SIZE_RANGE.minH)

            node.style({ width: w, height: h })
        })
        cy.endBatch()
    }
}
