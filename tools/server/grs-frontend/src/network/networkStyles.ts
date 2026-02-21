/**
 * Cytoscape style definitions for the network diagram.
 *
 * Node shapes:
 *   - gene: round-rectangle (compound parent when species visible)
 *   - species: ellipse (child of gene compound)
 *   - reaction: small dot, shows rate label
 *   - orphan species (no gene parent): circle, bigger than child species
 *
 * CSS classes:
 *   - `.excluded`: hidden via display:none (ModelFilter)
 *   - `.dimmed`: low opacity (SelectionSync)
 *   - `.highlighted`: bold border (SelectionSync)
 *   - `.species-view`: applied to regulatory edges when in species view
 *   - `.compound-parent`: applied to gene nodes with visible children
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

/** Orphan species size (circle, bigger than child species). */
export const ORPHAN_SPECIES_SIZE = 30

/** Reaction node size. */
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
        // -- base node (no borders) --
        {
            selector: 'node',
            style: {
                'label': 'data(label)',
                'text-valign': 'center' as any,
                'text-halign': 'center' as any,
                'font-size': 3,
                'font-family': FONT_FAMILY,
                'border-width': 0,
                'background-color': 'data(colour)',
                'text-wrap': 'ellipsis' as any,
                'text-max-width': '120px',
            } as any,
        },
        // -- gene node --
        {
            selector: 'node.gene',
            style: {
                'shape': 'round-rectangle',
                'width': GENE_BASE.width,
                'height': GENE_BASE.height,
                'text-valign': 'center' as any,
                'font-size': 14,
                'color': t.network.geneLabelText,
                'padding': '6px',
                'min-width': `${GENE_BASE.width}px`,
                'min-height': `${GENE_BASE.height}px`,
            } as any,
        },
        // -- compound gene (has visible children): label above, transparent bg --
        {
            selector: 'node.compound-parent',
            style: {
                'text-valign': 'top' as any,
                'text-margin-y': -8,
                'background-opacity': 0.25,
            } as any,
        },
        // -- orphan species (shown at gene level, circle) --
        {
            selector: 'node.orphan-species',
            style: {
                'shape': 'ellipse',
                'width': ORPHAN_SPECIES_SIZE,
                'height': ORPHAN_SPECIES_SIZE,
                'font-size': 8,
            } as any,
        },
        // -- species (child of gene compound) --
        {
            selector: 'node.species',
            style: {
                'shape': 'ellipse',
                'width': SPECIES_SIZE,
                'height': SPECIES_SIZE,
                'font-size': 2,
                'text-valign': 'bottom' as any,
                'text-margin-y': 1,
            } as any,
        },
        // -- reaction (small dot with rate label) --
        {
            selector: 'node.reaction',
            style: {
                'shape': 'ellipse',
                'width': REACTION_SIZE,
                'height': REACTION_SIZE,
                'label': 'data(rate)',
                'font-size': 1,
                'text-valign': 'center' as any,
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
        // -- highlighted gene (no border, just z-index boost) --
        {
            selector: 'node.highlighted',
            style: {
                'z-index': 10,
            } as any,
        },
        // -- edges (base style) --
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
        // -- gene-view regulatory edges: width scaled by binding site --
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
        // -- species-view regulatory edges: thin, no label, small arrows --
        {
            selector: 'edge.species-view',
            style: {
                'width': 0.5,
                'label': '',
                'arrow-scale': 0.3,
            } as any,
        },
        // -- produces (summary edges for cross-gene reaction products) --
        {
            selector: 'edge[kind="produces"]',
            style: {
                'width': 1,
                'line-style': 'dashed',
                'target-arrow-shape': 'triangle',
                'arrow-scale': 0.6,
            } as any,
        },
        {
            selector: 'edge[kind="substrate"]',
            style: {
                'width': 0.5,
                'line-color': t.network.speciesEdgeColour,
                'target-arrow-color': t.network.speciesEdgeColour,
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
                'line-color': t.network.speciesEdgeColour,
                'target-arrow-color': t.network.speciesEdgeColour,
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
