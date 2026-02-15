/**
 * Converts a UnionNetwork into Cytoscape element definitions.
 *
 * Filters out model-level container nodes.
 * Supports gene-only mode (hides species/reactions) and full mode.
 */
import type { UnionNetwork, Node, Link } from '@/types/network'
import { MODEL_NODE_KINDS, linkId } from '@/types/network'
import { lighten } from '@/utils/colorUtils'
import { getEdgeColour, shouldShowEdgeLabel } from './networkStyles'

/** Kinds that are only shown in detailed (zoomed-in) view. */
const DETAIL_KINDS = new Set(['species', 'reaction'])

/**
 * Convert union network to Cytoscape element definitions.
 *
 * @param network  - The union network data.
 * @param geneColours - Gene name -> hex colour mapping.
 * @param geneOnly - When true, only emit gene-level nodes + inter-gene edges.
 * @returns Array of Cytoscape element definitions (for cy.add / cy constructor).
 */
export function convertToElements(
    network: UnionNetwork,
    geneColours: Record<string, string>,
    geneOnly: boolean,
): cytoscape.ElementDefinition[] {
    const elements: cytoscape.ElementDefinition[] = []
    const geneNames = new Set(
        network.nodes.filter(n => n.kind === 'gene').map(n => n.name),
    )

    for (const node of network.nodes) {
        if (MODEL_NODE_KINDS.has(node.kind)) continue
        if (geneOnly && DETAIL_KINDS.has(node.kind)) continue

        const el = nodeElement(node, geneColours, geneNames)
        if (el) elements.push(el)
    }

    const emittedNodeIds = new Set(elements.map(e => e.data.id as string))

    for (const link of network.links) {
        if (!emittedNodeIds.has(link.from) || !emittedNodeIds.has(link.to)) continue

        elements.push(linkElement(link))
    }

    return elements
}

/**
 * Get only the detail-level elements (species + reactions + their edges).
 * Used by AdaptiveZoom to add/remove on zoom threshold crossing.
 */
export function getDetailElements(
    network: UnionNetwork,
    geneColours: Record<string, string>,
): cytoscape.ElementDefinition[] {
    const elements: cytoscape.ElementDefinition[] = []
    const geneNames = new Set(
        network.nodes.filter(n => n.kind === 'gene').map(n => n.name),
    )

    for (const node of network.nodes) {
        if (MODEL_NODE_KINDS.has(node.kind)) continue
        if (!DETAIL_KINDS.has(node.kind)) continue

        const el = nodeElement(node, geneColours, geneNames)
        if (el) elements.push(el)
    }

    // All node IDs including genes (for edge connectivity)
    const allNodeIds = new Set(
        network.nodes
            .filter(n => !MODEL_NODE_KINDS.has(n.kind))
            .map(n => n.name),
    )
    const detailNodeIds = new Set(elements.map(e => e.data.id as string))

    for (const link of network.links) {
        if (!allNodeIds.has(link.from) || !allNodeIds.has(link.to)) continue
        // Include edge if at least one endpoint is a detail node
        if (!detailNodeIds.has(link.from) && !detailNodeIds.has(link.to)) continue

        elements.push(linkElement(link))
    }

    return elements
}

// ============================================================================
// Internal helpers
// ============================================================================

function nodeElement(
    node: Node,
    geneColours: Record<string, string>,
    geneNames: Set<string>,
): cytoscape.ElementDefinition | null {
    const colour = getNodeColour(node, geneColours)
    const isOrphanSpecies = node.kind === 'species' && (node.parent === null || !geneNames.has(node.parent))
    const cssClass = isOrphanSpecies ? 'orphan-species' : node.kind

    return {
        data: {
            id: node.name,
            label: node.name,
            kind: node.kind,
            parent: undefined, // no compound nesting in cytoscape
            geneParent: node.parent,
            colour,
            ...node.properties,
        },
        classes: cssClass,
    }
}

function linkElement(link: Link): cytoscape.ElementDefinition {
    const edgeColour = getEdgeColour(link.kind)
    const label = shouldShowEdgeLabel(link.kind) ? formatLinkLabel(link) : ''

    return {
        data: {
            id: linkId(link),
            source: link.from,
            target: link.to,
            kind: link.kind,
            edgeColour,
            label,
            ...link.properties,
        },
        classes: link.kind,
    }
}

function getNodeColour(node: Node, geneColours: Record<string, string>): string {
    if (node.kind === 'gene') {
        const base = geneColours[node.name] ?? '#999999'
        return lighten(base, 0.4)
    }
    if (node.parent && geneColours[node.parent]) {
        return geneColours[node.parent]!
    }
    return '#999999'
}

function formatLinkLabel(link: Link): string {
    const affinity = link.properties?.at ?? link.properties?.affinity
    if (affinity !== undefined) {
        return `K=${Number(affinity).toFixed(2)}`
    }
    return ''
}
