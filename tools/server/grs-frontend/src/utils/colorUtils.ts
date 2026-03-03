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

/**
 * Reduce saturation of a hex colour by `amount` (0–1) without changing lightness.
 * amount = 0 → no change, amount = 1 → fully greyscale.
 */
export function desaturate(hex: string, amount: number): string {
    const { r, g, b } = parseHex(hex)

    // RGB → HSL
    const rn = r / 255, gn = g / 255, bn = b / 255
    const max = Math.max(rn, gn, bn)
    const min = Math.min(rn, gn, bn)
    const l = (max + min) / 2
    const d = max - min

    let h = 0
    let s = 0
    if (d !== 0) {
        s = d / (1 - Math.abs(2 * l - 1))
        if      (max === rn) h = ((gn - bn) / d + 6) % 6
        else if (max === gn) h = (bn - rn) / d + 2
        else                 h = (rn - gn) / d + 4
        h /= 6
    }

    const sNew = s * (1 - amount)

    // HSL → RGB
    const c = (1 - Math.abs(2 * l - 1)) * sNew
    const x = c * (1 - Math.abs((h * 6) % 2 - 1))
    const m = l - c / 2
    let r1 = 0, g1 = 0, b1 = 0
    const sector = Math.floor(h * 6)
    if      (sector === 0) { r1 = c; g1 = x }
    else if (sector === 1) { r1 = x; g1 = c }
    else if (sector === 2) { g1 = c; b1 = x }
    else if (sector === 3) { g1 = x; b1 = c }
    else if (sector === 4) { r1 = x; b1 = c }
    else                   { r1 = c; b1 = x }

    return rgbToHex((r1 + m) * 255, (g1 + m) * 255, (b1 + m) * 255)
}

/**
 * Rotate hue of a hex colour by amount in degrees (-180 to 180).
 * amount = 0 → no change, amount = 120 → shift by 120°
 */
export function rotateHue(hex: string, degrees: number): string {
    const { r, g, b } = parseHex(hex)

    // RGB → HSL
    const rn = r / 255, gn = g / 255, bn = b / 255
    const max = Math.max(rn, gn, bn)
    const min = Math.min(rn, gn, bn)
    const l = (max + min) / 2
    const d = max - min

    let h = 0
    let s = 0
    if (d !== 0) {
        s = d / (1 - Math.abs(2 * l - 1))
        if      (max === rn) h = ((gn - bn) / d + 6) % 6
        else if (max === gn) h = (bn - rn) / d + 2
        else                 h = (rn - gn) / d + 4
        h /= 6
    }

    // Rotate hue
    h = (h + degrees / 360) % 1
    if (h < 0) h += 1

    // HSL → RGB
    const c = (1 - Math.abs(2 * l - 1)) * s
    const x = c * (1 - Math.abs((h * 6) % 2 - 1))
    const m = l - c / 2
    let r1 = 0, g1 = 0, b1 = 0
    const sector = Math.floor(h * 6)
    if      (sector === 0) { r1 = c; g1 = x }
    else if (sector === 1) { r1 = x; g1 = c }
    else if (sector === 2) { g1 = c; b1 = x }
    else if (sector === 3) { g1 = x; b1 = c }
    else if (sector === 4) { r1 = x; b1 = c }
    else                   { r1 = c; b1 = x }

    return rgbToHex((r1 + m) * 255, (g1 + m) * 255, (b1 + m) * 255)
}