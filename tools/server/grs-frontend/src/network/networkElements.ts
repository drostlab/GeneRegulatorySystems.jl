/**
 * Converts a UnionNetwork into Cytoscape element definitions.
 *
 * Filters out model-level container nodes and machinery species.
 * Species with a gene parent get cytoscape `parent` set for compound nodes.
 */
import type { UnionNetwork, Node, Link } from '@/types/network'
import { MODEL_NODE_KINDS, MACHINERY_SPECIES, linkId } from '@/types/network'
import { lighten } from '@/utils/colorUtils'
import { getEdgeColour, shouldShowEdgeLabel } from './networkStyles'

/** Kinds that are only shown in detailed (zoomed-in) view. */
const DETAIL_KINDS = new Set(['species', 'reaction'])

/**
 * Gene-level elements: gene nodes, orphan species, and inter-gene edges.
 * Used for the default (zoomed-out) view.
 */
export function convertGeneElements(
    network: UnionNetwork,
    geneColours: Record<string, string>,
): cytoscape.ElementDefinition[] {
    const elements: cytoscape.ElementDefinition[] = []
    const geneNames = buildGeneNameSet(network)

    for (const node of network.nodes) {
        if (MODEL_NODE_KINDS.has(node.kind)) continue
        if (DETAIL_KINDS.has(node.kind)) continue
        if (isMachinery(node)) continue

        const el = nodeElement(node, geneColours, geneNames, false)
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
 * Detail-level elements: species (with compound parent), reactions, and their edges.
 * Used by AdaptiveZoom when zooming in past threshold.
 */
export function getDetailElements(
    network: UnionNetwork,
    geneColours: Record<string, string>,
): cytoscape.ElementDefinition[] {
    const elements: cytoscape.ElementDefinition[] = []
    const geneNames = buildGeneNameSet(network)

    for (const node of network.nodes) {
        if (MODEL_NODE_KINDS.has(node.kind)) continue
        if (!DETAIL_KINDS.has(node.kind)) continue
        if (isMachinery(node)) continue
        // Skip orphan species/reactions (already in gene-level view or unparented)
        if (!hasGeneParent(node, geneNames)) continue

        const el = nodeElement(node, geneColours, geneNames, true)
        if (el) elements.push(el)
    }

    // All non-excluded node IDs (for edge connectivity)
    const allNodeIds = new Set(
        network.nodes
            .filter(n => !MODEL_NODE_KINDS.has(n.kind) && !isMachinery(n))
            .map(n => n.name),
    )
    const detailNodeIds = new Set(elements.map(e => e.data.id as string))

    for (const link of network.links) {
        if (!allNodeIds.has(link.from) || !allNodeIds.has(link.to)) continue
        // Include edge only if at least one endpoint is a detail node
        if (!detailNodeIds.has(link.from) && !detailNodeIds.has(link.to)) continue
        elements.push(linkElement(link))
    }

    return elements
}

// ============================================================================
// Internal helpers
// ============================================================================

function buildGeneNameSet(network: UnionNetwork): Set<string> {
    return new Set(
        network.nodes.filter(n => n.kind === 'gene').map(n => n.name),
    )
}

function hasGeneParent(node: Node, geneNames: Set<string>): boolean {
    return node.parent !== null && geneNames.has(node.parent)
}

function isMachinery(node: Node): boolean {
    return MACHINERY_SPECIES.has(node.name)
}

function nodeElement(
    node: Node,
    geneColours: Record<string, string>,
    geneNames: Set<string>,
    asCompoundChild: boolean,
): cytoscape.ElementDefinition | null {
    const colour = getNodeColour(node, geneColours)
    const isOrphanSpecies = node.kind === 'species' && !hasGeneParent(node, geneNames)
    const cssClass = isOrphanSpecies ? 'orphan-species' : node.kind

    // Set cytoscape compound parent for species/reactions with a gene parent
    const isCompoundChild = asCompoundChild
        && (node.kind === 'species' || node.kind === 'reaction')
        && hasGeneParent(node, geneNames)
    const cytoscapeParent = isCompoundChild ? node.parent! : undefined

    return {
        data: {
            id: node.name,
            label: node.name,
            kind: node.kind,
            parent: cytoscapeParent,
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
    const isSelfLoop = link.from === link.to

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
        classes: `${link.kind}${isSelfLoop ? ' loop' : ''}`,
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
    const parts: string[] = []
    for (const [key, value] of Object.entries(link.properties ?? {})) {
        if (typeof value === 'number') {
            parts.push(`${key}=${value.toFixed(2)}`)
        } else if (value !== null && value !== undefined) {
            parts.push(`${key}=${String(value)}`)
        }
    }
    return parts.join(' ')
}
