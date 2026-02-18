/**
 * Colour utilities (hex-based)
 */

/**
 * Parse a hex colour string to RGB components.
 */
export function parseHex(hex: string): { r: number; g: number; b: number } {
    const clean = hex.replace('#', '')
    return {
        r: parseInt(clean.substring(0, 2), 16),
        g: parseInt(clean.substring(2, 4), 16),
        b: parseInt(clean.substring(4, 6), 16)
    }
}

/**
 * Convert RGB to hex
 */
export function rgbToHex(r: number, g: number, b: number): string {
    const toHex = (val: number) => Math.round(val).toString(16).padStart(2, '0')
    return `#${toHex(r)}${toHex(g)}${toHex(b)}`
}

/**
 * Linear interpolation between two colours
 */
export function lerpColor(color1: string, color2: string, t: number): string {
    const c1 = parseHex(color1)
    const c2 = parseHex(color2)
    
    return rgbToHex(
        c1.r + (c2.r - c1.r) * t,
        c1.g + (c2.g - c1.g) * t,
        c1.b + (c2.b - c1.b) * t
    )
}

/**
 * Lighten colour by mixing with white
 */
export function lighten(hex: string, amount: number): string {
    return lerpColor(hex, '#FFFFFF', amount)
}

/**
 * Adjust colour opacity (returns rgba string)
 */
export function darken(hex: string, factor: number = 0.7): string {
    return lerpColor(hex, '#000000', 1 - factor)
}

export function withOpacity(hex: string, opacity: number): string {
    const { r, g, b } = parseHex(hex)
    return `rgba(${r}, ${g}, ${b}, ${opacity})`
}
