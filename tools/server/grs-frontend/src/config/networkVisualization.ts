/**
 * Network visualization configuration
 *
 * Defines sizes and styling for different node/edge types.
 * Colours are imported from the centralised theme.
 */

import {
    EDGE_COLOURS,
    EDGE_COLOUR_FALLBACK,
    getTheme,
} from './theme'

export { EDGE_COLOURS }

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
 * Edge style configuration by kind
 */
export const EDGE_STYLES: Record<string, EdgeStyleConfig> = {
    activation: {
        colour: EDGE_COLOURS.activation!,
        width: 2
    },
    repression: {
        colour: EDGE_COLOURS.repression!,
        width: 2
    },
    proteolysis: {
        colour: EDGE_COLOURS.proteolysis!,
        width: 2
    },
    substrate: {
        colour: EDGE_COLOURS.substrate!,
        width: 1,
        style: 'dashed'
    },
    product: {
        colour: EDGE_COLOURS.product!,
        width: 1,
        style: 'dashed'
    }
}

/**
 * Node style defaults (uses light theme as the baseline).
 */
export function getNodeDefaults(isDark = false) {
    const t = getTheme(isDark)
    return {
        colour: t.network.nodeFallback,
        borderWidth: 2,
        borderColour: t.network.nodeBorder,
        fontSize: 10,
        fontFamily: 'Montserrat',
    }
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
    return EDGE_COLOURS[kind] || EDGE_COLOUR_FALLBACK
}

/**
 * Get edge style configuration
 */
export function getEdgeStyle(kind: string): EdgeStyleConfig {
    return EDGE_STYLES[kind] || {
        colour: EDGE_COLOUR_FALLBACK,
        width: 1
    }
}

/**
 * Should edge display a label with affinity/rate info?
 */
export function shouldShowEdgeLabel(kind: string): boolean {
    return ['activation', 'repression', 'proteolysis'].includes(kind)
}
