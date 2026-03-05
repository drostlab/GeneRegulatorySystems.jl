/**
 * Custom SciChart modifier for phase-space hover interaction.
 *
 * Uses SciChart's built-in hitTestProvider per scatter series for reliable
 * coordinate conversion (handles sub-surface offsets and DPI scaling).
 * Provides path dimming, tooltip, and hover callback.
 */
import {
    ChartModifierBase2D,
    EChart2DModifierType,
    type ModifierMouseArgs,
    type IRenderableSeries,
    DpiHelper,
} from "scichart"

const HIT_TEST_RADIUS_PX = 15
const DIM_OPACITY = 0.12

export type HoverInfo = { t: number; path: string }
type HoverCallback = (info: HoverInfo | null) => void

/** Extract path name from a scatter series dataSeriesName like "scatter:k3-1". */
function extractPath(series: IRenderableSeries): string | null {
    const name = series.dataSeries?.dataSeriesName
    if (!name?.startsWith('scatter:')) return null
    return name.substring(8)
}

export class PhaseSpaceHoverModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private hoverCallback?: HoverCallback
    private hoveredPath: string | null = null
    private lastHoverInfo: HoverInfo | null = null
    private tooltipDiv: HTMLDivElement | null = null
    /** Lookup from path -> time for each scatter data point index. */
    private pathTimeMap = new Map<string, number[]>()

    /** Register the hover callback (fires with nearest point info, or null on leave). */
    onHover(cb: HoverCallback): void {
        this.hoverCallback = cb
    }

    /** Store time values per path so we can resolve dataSeriesIndex -> t. */
    setPathTimes(pathTimes: Map<string, number[]>): void {
        this.pathTimeMap = pathTimes
    }

    override modifierMouseMove(args: ModifierMouseArgs): void {
        super.modifierMouseMove(args)
        if (!this.mousePoint || !this.isAttached) return

        const x = this.mousePoint.x * DpiHelper.PIXEL_RATIO
        const y = this.mousePoint.y * DpiHelper.PIXEL_RATIO
        const radius = HIT_TEST_RADIUS_PX * DpiHelper.PIXEL_RATIO

        let bestDist = Infinity
        let bestPath: string | null = null
        let bestIndex = -1

        // Hit-test only scatter series (one per path)
        for (const rs of this.parentSurface.renderableSeries.asArray()) {
            const path = extractPath(rs)
            if (!path) continue

            const hitInfo = rs.hitTestProvider.hitTestDataPoint(x, y, radius)
            if (hitInfo.isHit && hitInfo.distance < bestDist) {
                bestDist = hitInfo.distance
                bestPath = path
                bestIndex = hitInfo.dataSeriesIndex
            }
        }

        if (!bestPath || bestIndex < 0) {
            this._clearHover(args)
            return
        }

        const times = this.pathTimeMap.get(bestPath)
        const t = times?.[bestIndex]
        if (t === undefined) {
            this._clearHover(args)
            return
        }

        // Skip redundant events for same point
        if (this.lastHoverInfo?.t === t && this.lastHoverInfo?.path === bestPath) {
            this._updateTooltipPosition(args)
            return
        }

        this.lastHoverInfo = { t, path: bestPath }

        if (this.hoveredPath !== bestPath) {
            this.hoveredPath = bestPath
            this._dimPathsExcept(bestPath)
        }

        this._showTooltip(`${bestPath}\nt = ${t.toFixed(2)}`, args)
        this.hoverCallback?.({ t, path: bestPath })
    }

    override modifierMouseLeave(args: ModifierMouseArgs): void {
        super.modifierMouseLeave(args)
        this._clearHover(args)
    }

    dispose(): void {
        if (this.tooltipDiv) {
            document.body.removeChild(this.tooltipDiv)
            this.tooltipDiv = null
        }
    }

    // ------------------------------------------------------------------
    // Path dimming
    // ------------------------------------------------------------------

    private _dimPathsExcept(activePath: string): void {
        if (!this.isAttached) return
        for (const rs of this.parentSurface.renderableSeries.asArray()) {
            const name = rs.dataSeries?.dataSeriesName ?? ''
            if (name.startsWith('__')) continue // skip highlight
            const isLine = name.startsWith('line:')
            const isScatter = name.startsWith('scatter:')
            if (!isLine && !isScatter) continue
            const path = name.substring(name.indexOf(':') + 1)
            rs.opacity = path === activePath ? 1 : DIM_OPACITY
        }
    }

    private _restorePathOpacity(): void {
        if (!this.isAttached) return
        for (const rs of this.parentSurface.renderableSeries.asArray()) {
            const name = rs.dataSeries?.dataSeriesName ?? ''
            if (name.startsWith('line:') || name.startsWith('scatter:')) {
                rs.opacity = 1
            }
        }
    }

    // ------------------------------------------------------------------
    // Tooltip
    // ------------------------------------------------------------------

    private _showTooltip(text: string, args: ModifierMouseArgs): void {
        if (!this.tooltipDiv) {
            this.tooltipDiv = this._createTooltipDiv()
        }
        this.tooltipDiv.textContent = text
        const ne = args.nativeEvent
        if (ne) {
            this.tooltipDiv.style.left = `${ne.clientX + 12}px`
            this.tooltipDiv.style.top = `${ne.clientY - 20}px`
        }
        this.tooltipDiv.style.display = 'block'
    }

    private _updateTooltipPosition(args: ModifierMouseArgs): void {
        if (!this.tooltipDiv || this.tooltipDiv.style.display === 'none') return
        const ne = args.nativeEvent
        if (ne) {
            this.tooltipDiv.style.left = `${ne.clientX + 12}px`
            this.tooltipDiv.style.top = `${ne.clientY - 20}px`
        }
    }

    private _hideTooltip(): void {
        if (this.tooltipDiv) {
            this.tooltipDiv.style.display = 'none'
        }
    }

    private _createTooltipDiv(): HTMLDivElement {
        const el = document.createElement('div')
        el.className = 'grs-tooltip'
        Object.assign(el.style, {
            position: 'fixed',
            display: 'none',
            pointerEvents: 'none',
            zIndex: '9999',
            whiteSpace: 'pre',
        })
        document.body.appendChild(el)
        return el
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private _clearHover(_args: ModifierMouseArgs): void {
        if (this.hoveredPath !== null) {
            this.hoveredPath = null
            this.lastHoverInfo = null
            this._restorePathOpacity()
            this._hideTooltip()
            this.hoverCallback?.(null)
        }
    }
}
