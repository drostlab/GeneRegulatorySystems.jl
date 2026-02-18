/** Centralised chart styling constants. */

import { getTheme } from '@/config/theme'



export const CHART_FONT_SIZES = {
    label: 10,
    title: 12,
    annotation: 9
} as const

/** Default left-axis thickness (px). Counts panel uses a narrower value. */
export const AXIS_THICKNESS = 23
export const AXIS_THICKNESS_NARROW = 23

/** Palette for colouring schedule timeline segments by model path. */
export function getSegmentPalette(isDark: boolean): readonly string[] {
    return getTheme(isDark).timeline.segmentPalette
}

/** Default segment palette (light mode). Used where isDark is not available. */
export const SEGMENT_PALETTE = getTheme(false).timeline.segmentPalette
