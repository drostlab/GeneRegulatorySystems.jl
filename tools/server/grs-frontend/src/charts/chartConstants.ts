/** Centralised chart styling constants. */

export const CHART_FONT_FAMILY = "Arial"

export const CHART_FONT_SIZES = {
    label: 10,
    title: 12,
    annotation: 9
} as const

/** Default left-axis thickness (px). Counts panel uses a narrower value. */
export const AXIS_THICKNESS = 50
export const AXIS_THICKNESS_NARROW = 44

/** Palette for colouring schedule timeline segments by model path. */
export const SEGMENT_PALETTE = [
    "#B3D9FF", "#FFD9B3", "#B3FFD9", "#FFB3D9",
    "#D9B3FF", "#D9FFB3", "#FFE6B3", "#B3FFE6"
] as const
