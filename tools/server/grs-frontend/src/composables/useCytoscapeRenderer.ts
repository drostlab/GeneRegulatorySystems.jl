/**
 * Cytoscape network renderer
 * Converts GRS network data to Cytoscape format
 */
import type { Network } from '@/types/network'
import { lighten } from '@/utils/colorUtils'
import {
    getEdgeColour,
    shouldShowEdgeLabel,
    NODE_DEFAULTS,
    NODE_SIZES
} from '@/config/networkVisualization'

/**
 * Convert network to Cytoscape elements
 */
export function convertToElements(network: Network, geneColours: Record<string, string> = {}): any[] {
    const elements: any[] = []
    
    // Add nodes
    for (const node of network.nodes) {
        const nodeColour = getNodeColour(node, geneColours)
        
        elements.push({
            data: {
                id: node.name,
                label: node.name,
                kind: node.kind,
                parent: node.parent,
                colour: nodeColour,
                ...node.properties
            },
            classes: node.kind
        })
    }
    
    // Add links as edges
    for (const link of network.links) {
        const edgeColour = getEdgeColour(link.kind)
        const label = shouldShowEdgeLabel(link.kind) ? formatLinkLabel(link) : ''
        
        elements.push({
            data: {
                id: `${link.from}_${link.to}`,
                source: link.from,
                target: link.to,
                kind: link.kind,
                edgeColour,
                label,
                ...link.properties
            },
            classes: link.kind
        })
    }
    
    return elements
}

function getNodeColour(node: any, geneColours: Record<string, string>): string {
    if (node.kind === 'gene') {
        const base = geneColours[node.name] || NODE_DEFAULTS.colour
        return lighten(base, 0.4)
    }
    
    if (node.parent && geneColours[node.parent]) {
        return geneColours[node.parent]
    }
    
    return NODE_DEFAULTS.colour
}

function formatLinkLabel(link: any): string {
    const affinity = link.properties?.at || link.properties?.affinity
    if (affinity !== undefined) {
        return `K=${Number(affinity).toFixed(2)}`
    }
    return ''
}

/**
 * Cytoscape style definitions
 */
export function getDefaultStyles(): any[] {
    return [
        {
            selector: 'node',
            style: {
                'content': 'data(label)',
                'text-valign': 'bottom',
                'text-halign': 'center',
                'font-size': NODE_DEFAULTS.fontSize,
                'font-family': NODE_DEFAULTS.fontFamily,
                'border-width': NODE_DEFAULTS.borderWidth,
                'border-color': NODE_DEFAULTS.borderColour,
                'background-color': 'data(colour)'
            }
        },
        {
            selector: 'node[kind="gene"]',
            style: {
                'shape': 'rectangle',
                'width': NODE_SIZES.gene.width,
                'height': NODE_SIZES.gene.height,
                'padding': '20px',
                'text-valign': 'top',
                'text-margin-y': -20,
                'font-size': 50,
                'background-color': 'data(colour)'
            }
        },
        {
            selector: 'node[kind="species"]',
            style: {
                'shape': 'ellipse',
                'width': NODE_SIZES.species.width,
                'height': NODE_SIZES.species.height
            }
        },
        {
            selector: 'node[kind="reaction"]',
            style: {
                'shape': 'diamond',
                'width': NODE_SIZES.reaction.width,
                'height': NODE_SIZES.reaction.height
            }
        },
        {
            selector: 'node[kind="differentiator"]',
            style: {
                'shape': 'hexagon',
                'width': NODE_SIZES.differentiator.width,
                'height': NODE_SIZES.differentiator.height
            }
        },
        {
            selector: 'edge',
            style: {
                'width': 2,
                'line-color': 'data(edgeColour)',
                'target-arrow-color': 'data(edgeColour)',
                'target-arrow-shape': 'triangle',
                'curve-style': 'bezier',
                'content': 'data(label)',
                'font-size': 8,
                'text-rotation': 'autorotate',
                'text-margin-y': -10
            }
        },
        {
            selector: 'edge[kind="repression"]',
            style: {
                'target-arrow-shape': 'tee'
            }
        },
        {
            selector: 'edge[kind="substrate"], edge[kind="product"]',
            style: {
                'line-style': 'dashed',
                'width': 1
            }
        }
    ]
}

/**
 * Cytoscape layout configuration
 */
export function getDefaultLayout(): any {
    return {
        name: 'fcose',
        quality: 'proof',
        randomize: false,
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
        initialEnergyOnIncremental: 0.3
    }
}
