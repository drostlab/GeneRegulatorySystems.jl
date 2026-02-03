/**
 * Network visualization configuration
 * 
 * Defines colours, sizes, and styling for different node/edge types.
 * Separated from rendering logic to allow easy customization.
 */

export interface EdgeStyleConfig {
    colour: string
    width?: number
    style?: 'solid' | 'dashed' | 'dotted'
}

export interface NodeStyleConfig {
    shape: string
    size: { width: number; height: number }
    colour: string
}

/**
 * Edge colour configuration by kind
 */
export const EDGE_COLOURS: Record<string, string> = {
    activation: '#787878',
    repression: '#e16868',
    proteolysis: '#FF7F00',
    substrate: '#999999',
    product: '#666666',
    next: '#4DAF4A',
    alternative: '#984EA3'
}

/**
 * Edge style configuration by kind
 */
export const EDGE_STYLES: Record<string, EdgeStyleConfig> = {
    activation: {
        colour: EDGE_COLOURS.activation,
        width: 2
    },
    repression: {
        colour: EDGE_COLOURS.repression,
        width: 2
    },
    proteolysis: {
        colour: EDGE_COLOURS.proteolysis,
        width: 2
    },
    substrate: {
        colour: EDGE_COLOURS.substrate,
        width: 1,
        style: 'dashed'
    },
    product: {
        colour: EDGE_COLOURS.product,
        width: 1,
        style: 'dashed'
    }
}

/**
 * Node style defaults
 */
export const NODE_DEFAULTS = {
    colour: '#999999',
    borderWidth: 2,
    borderColour: '#333',
    fontSize: 10,
    fontFamily: 'Montserrat'
}

/**
 * Node size configuration by kind
 */
export const NODE_SIZES: Record<string, { width: number; height: number }> = {
    gene: { width: 180, height: 80 },
    species: { width: 60, height: 60 },
    reaction: { width: 40, height: 40 },
    differentiator: { width: 50, height: 50 }
}

/**
 * Get edge colour by kind
 */
export function getEdgeColour(kind: string): string {
    return EDGE_COLOURS[kind] || EDGE_COLOURS.substrate
}

/**
 * Get edge style configuration
 */
export function getEdgeStyle(kind: string): EdgeStyleConfig {
    return EDGE_STYLES[kind] || {
        colour: EDGE_COLOURS.substrate,
        width: 1
    }
}

/**
 * Should edge display a label with affinity/rate info?
 */
export function shouldShowEdgeLabel(kind: string): boolean {
    return ['activation', 'repression', 'proteolysis'].includes(kind)
}
