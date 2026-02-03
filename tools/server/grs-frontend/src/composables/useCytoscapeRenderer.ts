/**
 * Cytoscape rendering composable
 * 
 * Isolates all Cytoscape-specific logic for network visualization.
 * Makes it easy to swap rendering engines in the future.
 */
import type { Network, Node, Edge } from '@/types/network'
import { desaturateAndLighten } from '@/utils/colorUtils'
import { 
    getEdgeColour, 
    shouldShowEdgeLabel,
    NODE_DEFAULTS,
    NODE_SIZES 
} from '@/config/networkVisualization'

/**
 * Convert network to Cytoscape element format
 */
export function convertToElements(network: Network, geneColours: Record<string, string> = {}): any[] {
    const elements: any[] = []
    
    // Add nodes
    for (const node of network.nodes) {
        const colour = getNodeColour(node, geneColours)
        
        elements.push({
            data: {
                id: node.id,
                label: node.label || node.id,
                kind: node.kind,
                parent: node.parent,
                colour,
                ...node.properties
            },
            classes: node.kind
        })
    }
    
    // Add edges
    for (const edge of network.edges) {
        const edgeColour = getEdgeColour(edge.kind)
        const edgeLabel = shouldShowEdgeLabel(edge.kind) ? getEdgeLabel(edge) : ''
        
        elements.push({
            data: {
                id: `${edge.source}-${edge.target}`,
                source: edge.source,
                target: edge.target,
                kind: edge.kind,
                edgeColour,
                label: edgeLabel,
                ...edge.properties
            },
            classes: edge.kind
        })
    }
    
    return elements
}

/**
 * Get node colour based on type and parent
 */
function getNodeColour(node: Node, geneColours: Record<string, string>): string {
    if (node.kind === 'gene') {
        const baseColour = geneColours[node.id] || NODE_DEFAULTS.colour
        return desaturateAndLighten(baseColour)
    }
    
    // Child nodes inherit parent gene colour
    if (node.parent && geneColours[node.parent]) {
        return geneColours[node.parent]
    }
    
    return NODE_DEFAULTS.colour
}



/**
 * Get edge label from properties (affinity/rate)
 */
function getEdgeLabel(edge: Edge): string {
    const affinity = edge.properties.at || edge.properties.affinity
    if (affinity !== undefined) {
        return `K=${Number(affinity).toFixed(2)}`
    }
    return ''
}



/**
 * Get default Cytoscape styles
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
                'font-family': NODE_DEFAULTS.fontFamily,
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
            selector: 'edge[kind="substrate"]',
            style: {
                'line-style': 'dashed',
                'width': 1
            }
        },
        {
            selector: 'edge[kind="product"]',
            style: {
                'line-style': 'dashed',
                'width': 1
            }
        }
    ]
}

/**
 * Get default Cytoscape layout configuration
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
