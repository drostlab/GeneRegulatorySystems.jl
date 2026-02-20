/**
 * Cytoscape style definitions for the network diagram.
 *
 * Node shapes:
 *   - gene: round-rectangle (compound parent when species visible)
 *   - species: ellipse (child of gene compound)
 *   - reaction: tiny dot, no label
 *   - orphan species (no gene parent): shown at gene level, 70% size
 *
 * CSS classes:
 *   - `.excluded`: hidden via display:none (ModelFilter)
 *   - `.dimmed`: low opacity (SelectionSync)
 *   - `.highlighted`: blue border (SelectionSync)
 *   - `.loop`: self-loop edge styling
 */

import {
    EDGE_COLOURS as THEME_EDGE_COLOURS,
    EDGE_COLOUR_FALLBACK,
    DIM_OPACITY as THEME_DIM_OPACITY,
    getTheme,
} from '@/config/theme'

const FONT_FAMILY = 'Montserrat'

/** Edge colours re-exported from theme for backward compat. */
export const EDGE_COLOURS = THEME_EDGE_COLOURS

/** Gene node base dimensions (scaled by protein count). */
export const GENE_BASE = { width: 120, height: 50 }

/** Min/max gene node dimensions for dynamic sizing (wider range for visibility). */
export const GENE_SIZE_RANGE = { minW: 80, maxW: 250, minH: 40, maxH: 100 }

/** Species node size (small enough to fit inside gene in tight grid). */
export const SPECIES_SIZE = 10

/** Orphan species (no gene parent) size = 70% of gene. */
export const ORPHAN_SPECIES_SIZE = { width: GENE_BASE.width * 0.7, height: GENE_BASE.height * 0.7 }

/** Reaction node size (tiny dot). */
export const REACTION_SIZE = 3

/** Opacity for dimmed (unselected / excluded) elements. */
export const DIM_OPACITY = THEME_DIM_OPACITY

export function getEdgeColour(kind: string): string {
    return EDGE_COLOURS[kind] ?? EDGE_COLOUR_FALLBACK
}

export function shouldShowEdgeLabel(_kind: string): boolean {
    return true
}

/**
 * Default Cytoscape stylesheet.
 */
export function buildStylesheet(isDark = false): any[] {
    const t = getTheme(isDark)
    return [
        // -- base node --
        {
            selector: 'node',
            style: {
                'label': 'data(label)',
                'text-valign': 'center' as any,
                'text-halign': 'center' as any,
                'font-size': 3,
                'font-family': FONT_FAMILY,
                'border-width': 1.5,
                'border-color': t.network.nodeBorder,
                'background-color': 'data(colour)',
                'text-wrap': 'ellipsis' as any,
                'text-max-width': '120px',
            } as any,
        },
        // -- gene (also serves as compound parent when species visible) --
        {
            selector: 'node.gene',
            style: {
                'shape': 'round-rectangle',
                'width': GENE_BASE.width,
                'height': GENE_BASE.height,
                'text-valign': 'center' as any,
                'font-size': 14,
                'padding': '6px',
                'min-width': `${GENE_BASE.width}px`,
                'min-height': `${GENE_BASE.height}px`,
            } as any,
        },
        // -- compound gene (has visible children): label above --
        {
            selector: '$node > node',
            style: {
                'text-valign': 'top' as any,
                'text-margin-y': -8,
            } as any,
        },
        // -- orphan species (shown at gene level) --
        {
            selector: 'node.orphan-species',
            style: {
                'shape': 'ellipse',
                'width': ORPHAN_SPECIES_SIZE.width,
                'height': ORPHAN_SPECIES_SIZE.height,
                'font-size': 10,
            } as any,
        },
        // -- species --
        {
            selector: 'node.species',
            style: {
                'shape': 'ellipse',
                'width': SPECIES_SIZE,
                'height': SPECIES_SIZE,
                'font-size': 2,
                'border-width': 0.2,
                'text-valign': 'bottom' as any,
                'text-margin-y': 1,
            } as any,
        },
        // -- reaction (tiny dot) --
        {
            selector: 'node.reaction',
            style: {
                'shape': 'ellipse',
                'width': REACTION_SIZE,
                'height': REACTION_SIZE,
                'label': '',
                'border-width': 0,
                'background-color': t.network.reactionBg,
            } as any,
        },
        // -- excluded (hidden by ModelFilter) --
        {
            selector: '.excluded',
            style: {
                'display': 'none',
            } as any,
        },
        // -- dimmed --
        {
            selector: 'node.dimmed',
            style: {
                'opacity': DIM_OPACITY,
            } as any,
        },
        {
            selector: 'edge.dimmed',
            style: {
                'opacity': DIM_OPACITY,
            } as any,
        },
        // -- highlighted gene --
        {
            selector: 'node.highlighted',
            style: {
                'border-width': 3,
                'border-color': t.network.highlightBorder,
                'z-index': 10,
            } as any,
        },
        // -- edges (gene-level regulatory: thick) --
        {
            selector: 'edge',
            style: {
                'width': 1,
                'label': 'data(label)',
                'line-color': 'data(edgeColour)',
                'target-arrow-color': 'data(edgeColour)',
                'target-arrow-shape': 'triangle',
                'curve-style': 'bezier',
                'font-size': 7,
                'font-family': FONT_FAMILY,
                'color': t.network.edgeLabelText,
                'edge-distances': 'node-position',
                'text-rotation': 'autorotate' as any,
                'text-margin-y': -8,
                'text-background-color': t.network.edgeLabelBg,
                'text-background-opacity': 0.7,
                'text-background-padding': '2px',
                'z-index': 109,
            } as any,
        },
        {
            selector: 'edge[kind="activation"], edge[kind="repression"]',
            style: {
                'width': 'mapData(at, 0.1, 10, 5, 1)',
            } as any,
        },
        {
            selector: 'edge[kind="proteolysis"]',
            style: {
                'width': 1.5,
            } as any,
        },
        {
            selector: 'edge[kind="repression"]',
            style: {
                'target-arrow-shape': 'tee',
            } as any,
        },
        {
            selector: 'edge[kind="substrate"]',
            style: {
                'width': 0.5,
                'font-size': 2,
                'curve-style': 'unbundled-bezier',
                'control-point-step-size': 4,
                'target-arrow-shape': 'none',
                'text-margin-y': -1,
                'text-background-opacity': 0,
                'color': t.network.speciesEdgeLabelText,
            } as any,
        },

        {
            selector: 'edge[kind="product"]',
            style: {
                'width': 0.5,
                'font-size': 2,
                'arrow-scale': 0.2,
                'curve-style': 'unbundled-bezier',
                'control-point-step-size': 4,
                'text-margin-y': -1,
                'text-background-opacity': 0,
                'color': t.network.speciesEdgeLabelText,
            } as any,
        },
        {
            selector: 'edge:loop',
            style: {
                'curve-style': 'unbundled-bezier',
                'control-point-step-size': 100,
                'loop-sweep': '60deg',
                'text-background-opacity': 0,
            } as any,
        },
    ]
}
