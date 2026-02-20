/**
 * Centralised colour and style tokens for the entire frontend.
 *
 * Architecture
 * ============
 * 1. PALETTES: raw hex scales — the only place hex values are defined.
 * 2. MODE THEMES: light / dark objects that reference palette entries.
 *    Both typed as ThemeMode so they are guaranteed to have the same shape.
 * 3. Edge colours: mode-independent (always visible on both backgrounds).
 * 4. getTheme(isDark): returns the resolved ThemeMode for the active mode.
 *
 * Consumers
 * ---------
 * - PrimeVue preset (main.ts): reads `palette.*` for primary / info / success.
 * - SciChart panels / modifiers: call getTheme() for hex strings.
 * - Cytoscape network: calls getTheme() for hex strings.
 * - CSS / Vue components: use PrimeVue CSS vars (--p-*) where possible,
 *   or import getTheme() when a resolved value is needed.
 */

import { type IThemeProvider, SciChartJSDarkv2Theme, SciChartJSLightTheme } from 'scichart'
import logging from '@/utils/logging'

const log = logging.getLogger('theme')

// ═══════════════════════════════════════════════════════════════════════════
// 1. PALETTES  (single source of hex truth)
// ═══════════════════════════════════════════════════════════════════════════

/** Julia-inspired red — used as PrimeVue primary. Aura built-in red scale. */
export const RED = {
    50:  '#fef2f2',
    100: '#fee2e2',
    200: '#fecaca',
    300: '#fb9b9b',
    400: '#f37d7d',
    500: '#e87c7c',
    600: '#ca6d6d',
    700: '#9e6060',
    800: '#5a3737',
    900: '#3e2727',
    950: '#030202',
} as const

/** Julia-inspired purple — used as PrimeVue info. H=280, S tapers with L. */
export const PURPLE = {
    50:  '#f6f1f8',
    100: '#ebe0f0',
    200: '#d6c2e0',
    300: '#c4acd1',
    400: '#b3a3bd',
    500: '#9a7ea8',
    600: '#887792',
    700: '#685a6f',
    800: '#524657',
    900: '#342d37',
    950: '#201c22',
} as const

/** Julia-inspired green — used as PrimeVue success / run button. Aura green. */
export const GREEN = {
    50:  '#f0fdf4',
    100: '#dcfce7',
    200: '#bbf7d0',
    300: '#86efac',
    400: '#4ade80',
    500: '#22c55e',
    600: '#16a34a',
    700: '#15803d',
    800: '#166534',
    900: '#14532d',
    950: '#052e16',
} as const

/** Neutral grey scale (zinc). Surfaces, text, borders. */
export const GREY = {
    0:   '#ffffff',
    50:  '#fafafa',
    100: '#f4f4f5',
    200: '#e4e4e7',
    300: '#d4d4d8',
    400: '#a1a1aa',
    500: '#71717a',
    600: '#52525b',
    700: '#3f3f46',
    800: '#27272a',
    900: '#18181b',
    950: '#09090b',
} as const

/** Exported palette aggregation for PrimeVue definePreset. */
export const palette = {
    red:    RED,
    purple: PURPLE,
    green:  GREEN,
    grey:   GREY,
} as const

// ═══════════════════════════════════════════════════════════════════════════
// 2. EDGE COLOURS  (mode-independent)
// ═══════════════════════════════════════════════════════════════════════════

export const EDGE_COLOURS: Record<string, string> = {
    activation:  '#787878',
    repression:  '#e16868',
    proteolysis: '#FF7F00',
    substrate:   '#999999',
    product:     '#666666',
    next:        '#4DAF4A',
    alternative: '#984EA3',
}

export const EDGE_COLOUR_FALLBACK = EDGE_COLOURS.substrate!

/** Opacity for dimmed (unselected) network elements. */
export const DIM_OPACITY = 0.3

// ═══════════════════════════════════════════════════════════════════════════
// 3. MODE THEMES  (light + dark, identical shape)
// ═══════════════════════════════════════════════════════════════════════════

export interface ThemeMode {
    /** Surface / background colours. */
    surface: {
        bg: string
        card: string
        border: string
    }
    /** Text colours. */
    text: {
        base: string
        muted: string
        dim: string
    }
    /** SciChart shared colours. */
    chart: {
        gridLine: string
        cursor: string
        cursorText: string
        tooltipBg: string
        tooltipFg: string
        fallbackSeries: string
    }
    /** Timeline panel. */
    timeline: {
        instant: {
            normal: { line: string; bg: string; text: string }
            hover:  { line: string; bg: string; text: string }
        }
        rect: {
            colour:   string
            normal:   { stroke: string; text: string }
            hover:    { stroke: string; text: string }
            selected: { fill: string; stroke: string; text: string }
        }
        segmentBoundary: string
    }
    /** Network diagram. */
    network: {
        reactionBg: string
        highlightBorder: string
        edgeLabelText: string
        /** Label text colour for species/reaction-level edges (substrate, product). */
        speciesEdgeLabelText: string
        edgeLabelBg: string
        dotGrid: string
        nodeBorder: string
        nodeFallback: string
    }
    /** SciChart IThemeProvider instance. */
    sciChartTheme: IThemeProvider
}

const light: ThemeMode = {
    surface: {
        bg:     GREY[50],
        card:   GREY[0],
        border: GREY[200],
    },
    text: {
        base:  GREY[950],
        muted: GREY[600],
        dim:   GREY[400],
    },
    chart: {
        gridLine:       GREY[100],
        cursor:         GREY[950],
        cursorText:     GREY[0],
        tooltipBg:      GREY[800],
        tooltipFg:      GREY[0],
        fallbackSeries: GREY[400],
    },
    timeline: {
        instant: {
            normal: { line: GREY[50],   bg: GREY[50],   text: GREY[600]   },
            hover:  { line: PURPLE[200], bg: PURPLE[200], text: GREY[950] },
        },
        rect: {
            colour:   GREY[200],
            normal:   { stroke: GREY[300], text: GREY[500] },
            hover:    { stroke: GREY[400], text: GREY[700] },
            selected: { fill: PURPLE[200], stroke: GREY[300], text: GREY[900] },
        },
        segmentBoundary: GREY[300],
    },
    network: {
        reactionBg:           GREY[400],
        highlightBorder:      GREY[950],
        edgeLabelText:        GREY[600],
        speciesEdgeLabelText: GREY[600],
        edgeLabelBg:          GREY[0],
        dotGrid:              GREY[300],
        nodeBorder:           GREY[800],
        nodeFallback:         GREY[400],
    },
    sciChartTheme: new SciChartJSLightTheme(),
}

const dark: ThemeMode = {
    surface: {
        bg:     GREY[950],
        card:   GREY[900],
        border: GREY[700],
    },
    text: {
        base:  GREY[50],
        muted: GREY[400],
        dim:   GREY[600],
    },
    chart: {
        gridLine:       GREY[700],
        cursor:         GREY[950],
        cursorText:     GREY[0],
        tooltipBg:      GREY[200],
        tooltipFg:      GREY[950],
        fallbackSeries: GREY[500],
    },
    timeline: {
        instant: {
            normal: { line: GREY[500],   bg: GREY[800],    text: GREY[300]   },
            hover:  { line: PURPLE[500], bg: PURPLE[500],  text: GREY[50] },
        },
        rect: {
            colour:   GREY[700],
            normal:   { stroke: GREY[600], text: GREY[400] },
            hover:    { stroke: GREY[400], text: GREY[200] },
            selected: { fill: PURPLE[800], stroke: PURPLE[400], text: GREY[50] },
        },
        segmentBoundary: GREY[700],
    },
    network: {
        reactionBg:           GREY[500],
        highlightBorder:      GREY[950],
        edgeLabelText:        GREY[100],
        speciesEdgeLabelText: GREY[800],
        edgeLabelBg:          GREY[800],
        dotGrid:              GREY[800],
        nodeBorder:           GREY[800],
        nodeFallback:         GREY[500],
    },
    sciChartTheme: new SciChartJSDarkv2Theme(),
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. THEME ACCESS
// ═══════════════════════════════════════════════════════════════════════════

/** Returns the fully resolved theme for the given mode. */
export function getTheme(isDark: boolean): ThemeMode {
    const t = isDark ? dark : light
    log.debug(`Resolved theme: ${isDark ? 'dark' : 'light'}`)
    return t
}
