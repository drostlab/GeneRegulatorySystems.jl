/**
 * NetworkView - main orchestrator for the Cytoscape network diagram.
 *
 * Owns the cytoscape instance and lifecycle. Creates and coordinates
 * sub-modules: AdaptiveZoom, ModelFilter, SelectionSync, DynamicsSync.
 *
 * Usage:
 *   const view = new NetworkView()
 *   await view.init(containerRef)
 *   view.setNetwork(unionNetwork, geneColours)
 *   // ...
 *   view.destroy()
 */
import type { Core } from 'cytoscape'
import type { Ref } from 'vue'
import type { UnionNetwork } from '@/types/network'
import cytoscape from 'cytoscape'
// @ts-ignore
import fcose from 'cytoscape-fcose'

import { convertToElements } from './networkElements'
import { buildStylesheet } from './networkStyles'
import { AdaptiveZoom } from './AdaptiveZoom'
import { ModelFilter } from './ModelFilter'
import { SelectionSync } from './SelectionSync'
import { DynamicsSync } from './DynamicsSync'

cytoscape.use(fcose)

export class NetworkView {
    private cy: Core | null = null
    private container: HTMLDivElement | null = null

    private adaptiveZoom = new AdaptiveZoom()
    private modelFilter = new ModelFilter()
    private selectionSync = new SelectionSync()
    private dynamicsSync = new DynamicsSync()

    private layoutTimeout: ReturnType<typeof setTimeout> | null = null

    /**
     * Initialise the cytoscape container.
     * Does not render anything until setNetwork() is called.
     */
    init(containerRef: Ref<HTMLDivElement | undefined>): void {
        if (!containerRef.value) return
        this.container = containerRef.value
        this.applyContainerBackground()
    }

    /**
     * Set or replace the union network. Destroys the old graph and rebuilds.
     */
    setNetwork(network: UnionNetwork, geneColours: Record<string, string>): void {
        this.destroyCytoscape()

        if (!this.container) return

        const elements = convertToElements(network, geneColours, true)
        console.debug(`[NetworkView] Rendering: ${elements.length} gene-level elements`)

        this.cy = cytoscape({
            container: this.container,
            elements,
            wheelSensitivity: 0.1,
            style: buildStylesheet(false),
            layout: { name: 'preset' }, // manual layout below
            userPanningEnabled: true,
            userZoomingEnabled: true,
            boxSelectionEnabled: false,
            selectionType: 'single',
        })

        // Run animated fcose layout
        this.runLayout()

        // Attach sub-modules after layout settles
        this.layoutTimeout = setTimeout(() => {
            if (!this.cy) return
            this.adaptiveZoom.attach(this.cy, network, geneColours)
            this.modelFilter.attach(this.cy)
            this.selectionSync.attach(this.cy)
            this.dynamicsSync.attach(this.cy)

            // When detail visibility changes, refresh model filter + selection
            this.adaptiveZoom.onDetailChange = (_visible: boolean) => {
                this.modelFilter.refresh()
                this.selectionSync.refresh()
            }
        }, 1200)
    }

    /** Destroy everything. */
    destroy(): void {
        if (this.layoutTimeout) {
            clearTimeout(this.layoutTimeout)
            this.layoutTimeout = null
        }
        this.destroyModules()
        this.destroyCytoscape()
        this.container = null
    }

    // ========================================================================
    // Internal
    // ========================================================================

    private runLayout(): void {
        if (!this.cy) return

        this.cy.layout({
            name: 'fcose',
            quality: 'proof',
            randomize: true,
            animate: true,
            animationDuration: 1000,
            fit: true,
            padding: 50,
            nodeDimensionsIncludeLabels: true,
            uniformNodeDimensions: false,
            packComponents: true,
            nodeRepulsion: 4500,
            idealEdgeLength: 100,
            edgeElasticity: 0.45,
            nestingFactor: 0.1,
            gravity: 0.25,
            numIter: 2500,
            tile: true,
            tilingPaddingVertical: 10,
            tilingPaddingHorizontal: 10,
            gravityRangeCompound: 1.5,
            gravityCompound: 1.0,
            gravityRange: 3.8,
            initialEnergyOnIncremental: 0.3,
        } as any).run()
    }

    private destroyModules(): void {
        this.adaptiveZoom.destroy()
        this.modelFilter.destroy()
        this.selectionSync.destroy()
        this.dynamicsSync.destroy()
    }

    private destroyCytoscape(): void {
        this.destroyModules()
        if (this.cy) {
            this.cy.destroy()
            this.cy = null
        }
    }

    private applyContainerBackground(): void {
        if (!this.container) return
        this.container.style.backgroundImage =
            'radial-gradient(circle, #d0d0d0 1px, transparent 1px)'
        this.container.style.backgroundSize = '30px 30px'
    }
}
