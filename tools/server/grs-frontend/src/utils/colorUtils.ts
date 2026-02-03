/**
 * Colour utility functions
 */

/**
 * Desaturate and lighten colour for gene backgrounds
 */
export function desaturateAndLighten(hex: string, saturationFactor = 0.8, lightnessBoost = 0.4): string {
    hex = hex.replace('#', '')
    
    const r = parseInt(hex.substring(0, 2), 16) / 255
    const g = parseInt(hex.substring(2, 4), 16) / 255
    const b = parseInt(hex.substring(4, 6), 16) / 255
    
    const max = Math.max(r, g, b)
    const min = Math.min(r, g, b)
    let h = 0
    let s = 0
    const l = (max + min) / 2
    
    if (max !== min) {
        const d = max - min
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
        
        switch (max) {
            case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break
            case g: h = ((b - r) / d + 2) / 6; break
            case b: h = ((r - g) / d + 4) / 6; break
        }
    }
    
    s = Math.min(1, s * saturationFactor)
    const newL = Math.min(1, l + lightnessBoost)
    
    const c = (1 - Math.abs(2 * newL - 1)) * s
    const x = c * (1 - Math.abs((h * 6) % 2 - 1))
    const m = newL - c / 2
    
    let r2 = 0, g2 = 0, b2 = 0
    if (h < 1/6) { r2 = c; g2 = x; b2 = 0 }
    else if (h < 2/6) { r2 = x; g2 = c; b2 = 0 }
    else if (h < 3/6) { r2 = 0; g2 = c; b2 = x }
    else if (h < 4/6) { r2 = 0; g2 = x; b2 = c }
    else if (h < 5/6) { r2 = x; g2 = 0; b2 = c }
    else { r2 = c; g2 = 0; b2 = x }
    
    const toHex = (val: number) => Math.round((val + m) * 255).toString(16).padStart(2, '0')
    return `#${toHex(r2)}${toHex(g2)}${toHex(b2)}`
}

/**
 * Blend between two colors based on a factor (0-1)
 */
export function blendColors(color1: string, color2: string, factor: number): string {
    const hex = (c: string) => {
        const result = c.replace('#', '')
        return {
            r: parseInt(result.substring(0, 2), 16),
            g: parseInt(result.substring(2, 4), 16),
            b: parseInt(result.substring(4, 6), 16)
        }
    }
    
    const c1 = hex(color1)
    const c2 = hex(color2)
    
    const r = Math.round(c1.r + (c2.r - c1.r) * factor)
    const g = Math.round(c1.g + (c2.g - c1.g) * factor)
    const b = Math.round(c1.b + (c2.b - c1.b) * factor)
    
    const toHex = (val: number) => val.toString(16).padStart(2, '0')
    return `#${toHex(r)}${toHex(g)}${toHex(b)}`
}
