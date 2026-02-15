/**
 * Model filtering module.
 *
 * Watches viewerStore.activeModelPath and hides/shows nodes+edges
 * based on the union network's model_exclusions.
 * Elements not present in the active model are removed from the graph
 * and stashed. On model switch, stashed elements are restored and new
 * exclusions are applied. Since positions come from the union layout,
 * nothing moves on model switch.
 */
import type { Core, Collection } from 'cytoscape'
import { watch, type WatchStopHandle } from 'vue'
import { useViewerStore } from '@/stores/viewerStore'
import { useScheduleStore } from '@/stores/scheduleStore'

export class ModelFilter {
    private cy: Core | null = null
    private stashed: Collection | null = null
    private stopWatch: WatchStopHandle | null = null

    attach(cy: Core): void {
        this.cy = cy
        this.stashed = cy.collection()

        this.stopWatch = watch(
            () => useViewerStore().activeModelPath,
            () => this.applyFilter(),
            { immediate: true },
        )
    }

    destroy(): void {
        this.stopWatch?.()
        this.stopWatch = null
        this.stashed = null
        this.cy = null
    }

    /** Re-apply the current model's exclusions. Call after elements are added/removed externally. */
    refresh(): void {
        this.applyFilter()
    }

    private applyFilter(): void {
        const cy = this.cy
        if (!cy) return

        const viewerStore = useViewerStore()
        const scheduleStore = useScheduleStore()
        const union = scheduleStore.unionNetwork
        if (!union) return

        const modelPath = viewerStore.activeModelPath
        if (!modelPath) return

        const exclusions = union.model_exclusions[modelPath]
        if (!exclusions) return

        cy.startBatch()

        // Restore previously stashed elements
        if (this.stashed && this.stashed.length > 0) {
            this.stashed.restore()
            this.stashed = cy.collection()
        }

        // Build exclusion sets
        const excludedNodes = new Set(exclusions.nodes)
        const excludedLinks = new Set(exclusions.links)

        // Remove excluded nodes
        const nodesToRemove = cy.nodes().filter(
            (n: any) => excludedNodes.has(n.id()),
        )
        // Remove excluded edges
        const edgesToRemove = cy.edges().filter(
            (e: any) => excludedLinks.has(`${e.data('source')}-${e.data('kind')}-${e.data('target')}`),
        )
        // Also remove edges connected to excluded nodes
        const connectedEdges = nodesToRemove.connectedEdges()

        const toRemove = nodesToRemove.union(edgesToRemove).union(connectedEdges)
        this.stashed = toRemove.remove()

        cy.endBatch()

        console.debug(`[ModelFilter] Model ${modelPath}: excluded ${nodesToRemove.length} nodes, ${edgesToRemove.length} edges`)
    }
}
