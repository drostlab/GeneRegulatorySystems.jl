/**
 * Cytoscape style definitions for the network diagram.
 *
 * Node shapes:
 *   - gene: round-rectangle, label inside
 *   - species: ellipse (circle)
 *   - reaction: tiny dot, no label
 *   - orphan species (no gene parent): shown at gene level, 70% size
 *
 * When species are visible, gene labels move above the shape.
 */

const FONT_FAMILY = 'Montserrat'

/** Edge colours by link kind. */
export const EDGE_COLOURS: Record<string, string> = {
    activation: '#787878',
    repression: '#e16868',
    proteolysis: '#FF7F00',
    substrate: '#999999',
    product: '#666666',
    next: '#4DAF4A',
    alternative: '#984EA3',
}

/** Gene node base dimensions (scaled by protein count). */
export const GENE_BASE = { width: 140, height: 55 }

/** Min/max gene node dimensions for dynamic sizing. */
export const GENE_SIZE_RANGE = { minW: 80, maxW: 220, minH: 40, maxH: 90 }

/** Species node size. */
export const SPECIES_SIZE = 40

/** Orphan species (no gene parent) size = 70% of gene. */
export const ORPHAN_SPECIES_SIZE = { width: GENE_BASE.width * 0.7, height: GENE_BASE.height * 0.7 }

/** Reaction node size (tiny dot). */
export const REACTION_SIZE = 6

/** Opacity for dimmed (unselected / excluded) elements. */
export const DIM_OPACITY = 0.15

/** Opacity for non-hovered but not dimmed elements. */
export const IDLE_OPACITY = 1.0

export function getEdgeColour(kind: string): string {
    return EDGE_COLOURS[kind] ?? '#999999'
}

export function shouldShowEdgeLabel(kind: string): boolean {
    return kind === 'activation' || kind === 'repression' || kind === 'proteolysis'
}

/**
 * Default Cytoscape stylesheet.
 * `speciesVisible` controls whether gene labels are inside or above the shape.
 */
export function buildStylesheet(speciesVisible: boolean): any[] {
    const geneLabelVAlign = speciesVisible ? 'top' : 'center'
    const geneLabelMarginY = speciesVisible ? -12 : 0

    return [
        // -- base node --
        {
            selector: 'node',
            style: {
                'label': 'data(label)',
                'text-valign': 'center' as any,
                'text-halign': 'center' as any,
                'font-size': 10,
                'font-family': FONT_FAMILY,
                'border-width': 1.5,
                'border-color': '#333',
                'background-color': 'data(colour)',
                'text-wrap': 'ellipsis' as any,
                'text-max-width': '120px',
            } as any,
        },
        // -- gene --
        {
            selector: 'node.gene',
            style: {
                'shape': 'round-rectangle',
                'width': GENE_BASE.width,
                'height': GENE_BASE.height,
                'text-valign': geneLabelVAlign as any,
                'text-margin-y': geneLabelMarginY,
                'font-size': 14,
                'font-weight': 'bold' as any,
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
                'font-size': 8,
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
                'background-color': '#888',
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
                'border-color': '#1a73e8',
                'z-index': 10,
            } as any,
        },
        // -- edges --
        {
            selector: 'edge',
            style: {
                'width': 2,
                'line-color': 'data(edgeColour)',
                'target-arrow-color': 'data(edgeColour)',
                'target-arrow-shape': 'triangle',
                'curve-style': 'bezier',
                'font-size': 8,
                'text-rotation': 'autorotate' as any,
                'text-margin-y': -10,
            } as any,
        },
        {
            selector: 'edge[kind="repression"]',
            style: {
                'target-arrow-shape': 'tee',
            } as any,
        },
        {
            selector: 'edge[kind="substrate"], edge[kind="product"]',
            style: {
                'line-style': 'dashed',
                'width': 1,
            } as any,
        },
    ]
}
