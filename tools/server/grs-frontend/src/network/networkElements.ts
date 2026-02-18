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
import { getTheme } from '@/config/theme'

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

    // Use species_type as label for species nodes, fallback to name
    const label = node.kind === 'species' && node.properties?.species_type
        ? String(node.properties.species_type)
        : node.name

    return {
        data: {
            id: node.name,
            label,
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

    // Extract "at" parameter for activation/repression edges (affects weight and width)
    const at = (link.properties.at as number) ?? 1
    // Weight: inverse of "at" so higher "at" = lower weight = tighter pull in layout
    const weight = 1 / Math.max(at, 0.1)

    return {
        data: {
            id: linkId(link),
            source: link.from,
            target: link.to,
            kind: link.kind,
            edgeColour,
            label,
            at,
            weight,
            ...link.properties,
        },
        classes: `${link.kind}${isSelfLoop ? ' loop' : ''}`,
    }
}

function getNodeColour(node: Node, geneColours: Record<string, string>): string {
    const fallback = getTheme(false).network.nodeFallback
    if (node.kind === 'gene') {
        const base = geneColours[node.name] ?? fallback
        return lighten(base, 0.4)
    }
    if (node.parent && geneColours[node.parent]) {
        return geneColours[node.parent]!
    }
    return fallback
}

function formatLinkLabel(link: Link): string {
    const entries = Object.entries(link.properties ?? {})
    if (entries.length === 0) return ''

    // If only one property, show just the value
    if (entries.length === 1) {
        const [key, value] = entries[0]!
        return formatPropertyValue(value, key)
    }

    // Multiple properties: show key=value pairs
    const parts: string[] = []
    for (const [key, value] of entries) {
        const formatted = formatPropertyValue(value, key)
        parts.push(`${key}=${formatted}`)
    }
    return parts.join(' ')
}

/**
 * Format a property value: integers without decimals for stoichiometry, 
 * floats with 2 decimals for others.
 */
function formatPropertyValue(value: any, key: string = ''): string {
    if (typeof value === 'number') {
        // Show stoichiometry without decimals, all other numbers with 2 decimals
        if (key === 'stoichiometry' && Number.isInteger(value)) {
            return String(value)
        }
        return value.toFixed(2)
    }
    return value !== null && value !== undefined ? String(value) : ''
}
