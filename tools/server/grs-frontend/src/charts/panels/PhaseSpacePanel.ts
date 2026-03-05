/**
 * PhaseSpacePanel -- BasePanel subclass for phase-space embedding views.
 *
 * Renders per-path trajectory lines + scatter points as a SciChartSubSurface.
 * Supports timepoint highlighting, hover tooltips (via PhaseSpaceHoverModifier),
 * path dimming, and click selection with full cross-panel sync.
 */
import {
    NumericAxis,
    XyDataSeries,
    FastLineRenderableSeries,
    XyScatterRenderableSeries,
    EllipsePointMarker,
    MouseWheelZoomModifier,
    ZoomPanModifier,
    ZoomExtentsModifier,
    CustomAnnotation,
} from "scichart"
import { BasePanel, type BasePanelOptions } from "./BasePanel"
import type { PhaseSpacePoint, PhaseSpaceResult } from "@/types/simulation"
import { CHART_FONT_SIZES } from "../chartConstants"
import { PhaseSpaceHoverModifier } from "../modifiers/PhaseSpaceHoverModifier"
export type { HoverInfo } from "../modifiers/PhaseSpaceHoverModifier"

const LINE_ALPHA = 0.45
const POINT_SIZE = 4
const HIGHLIGHT_SIZE = 14
const ARROW_SIZE = 8

/** Build an SVG triangle pointing right, rotated to `angleDeg`, filled with `colour`. */
function arrowSvg(colour: string, angleDeg: number): string {
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${ARROW_SIZE * 2}" height="${ARROW_SIZE * 2}">` +
        `<polygon points="${ARROW_SIZE},0 ${ARROW_SIZE * 2},${ARROW_SIZE} ${ARROW_SIZE},${ARROW_SIZE * 2}" ` +
        `fill="${colour}" transform="rotate(${angleDeg}, ${ARROW_SIZE}, ${ARROW_SIZE})" />` +
        `</svg>`
}

type PathSelectCallback = (path: string) => void

/** Append alpha to a '#rrggbb' hex colour. */
function withAlpha(hex: string, alpha: number): string {
    const r = parseInt(hex.slice(1, 3), 16)
    const g = parseInt(hex.slice(3, 5), 16)
    const b = parseInt(hex.slice(5, 7), 16)
    return `rgba(${r},${g},${b},${alpha})`
}


export class PhaseSpacePanel extends BasePanel {
    private result?: PhaseSpaceResult
    private highlightData?: XyDataSeries
    private highlightSeries?: XyScatterRenderableSeries
    private pathLineData = new Map<string, XyDataSeries>()
    private pathScatterData = new Map<string, XyDataSeries>()
    private pathLineSeries = new Map<string, FastLineRenderableSeries>()
    private pathScatterSeries = new Map<string, XyScatterRenderableSeries>()
    /** Pre-sorted (by t) points per path -- for highlight and hit-test. */
    private pathPoints = new Map<string, PhaseSpacePoint[]>()
    private arrowAnnotations: CustomAnnotation[] = []
    private pathSelectCallback?: PathSelectCallback
    private hoverModifier: PhaseSpaceHoverModifier

    constructor(options: BasePanelOptions) {
        super(options)

        const xAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "",
            labelStyle: { fontSize: CHART_FONT_SIZES.label },
            axisTitleStyle: { fontSize: CHART_FONT_SIZES.title },
            drawMajorBands: false,
            drawMinorGridLines: false,
        })
        const yAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "",
            labelStyle: { fontSize: CHART_FONT_SIZES.label },
            axisTitleStyle: { fontSize: CHART_FONT_SIZES.title },
            drawMajorBands: false,
            drawMinorGridLines: false,
            majorGridLineStyle: { color: this.theme.chart.gridLine },
            minorGridLineStyle: { color: this.theme.chart.gridLine },
        })
        this.surface.xAxes.add(xAxis)
        this.surface.yAxes.add(yAxis)

        // Phase space has its own zoom/pan (independent of timeseries)
        this.surface.chartModifiers.add(new MouseWheelZoomModifier())
        this.surface.chartModifiers.add(new ZoomPanModifier())
        this.surface.chartModifiers.add(new ZoomExtentsModifier())

        // Hover modifier handles hit-testing, tooltip, and path dimming
        this.hoverModifier = new PhaseSpaceHoverModifier()
        this.surface.chartModifiers.add(this.hoverModifier)

        this._createHighlightSeries()
    }

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    /** Set the phase-space result, rebuilding all series. */
    setPhaseSpaceData(result: PhaseSpaceResult): void {
        this._clearPathSeries()
        this.result = result

        // Group + sort by t
        const byPath = new Map<string, PhaseSpacePoint[]>()
        for (const pt of result.points) {
            const arr = byPath.get(pt.path)
            if (arr) arr.push(pt)
            else byPath.set(pt.path, [pt])
        }
        byPath.forEach(pts => pts.sort((a, b) => a.t - b.t))

        // Update axis titles
        const xAxis = this.surface.xAxes.get(0)
        const yAxis = this.surface.yAxes.get(0)
        if (xAxis) xAxis.axisTitle = result.axis_labels[0] ?? ""
        if (yAxis) yAxis.axisTitle = result.axis_labels[1] ?? ""

        // Temporarily remove highlight so new series go underneath, then re-add
        this.surface.renderableSeries.remove(this.highlightSeries!)

        byPath.forEach((pts, path) => {
            const xs = pts.map(p => p.x)
            const ys = pts.map(p => p.y)
            const pathColour = pts[0]!.colour

            const lineData = new XyDataSeries(this.wasmContext, {
                isSorted: false,
                dataSeriesName: `line:${path}`,
            })
            lineData.appendRange(xs, ys)

            const scatterData = new XyDataSeries(this.wasmContext, {
                isSorted: false,
                dataSeriesName: `scatter:${path}`,
            })
            scatterData.appendRange(xs, ys)

            const lineSeries = new FastLineRenderableSeries(this.wasmContext, {
                dataSeries: lineData,
                stroke: withAlpha(pathColour, LINE_ALPHA),
                strokeThickness: 1.5,
            })
            const scatterSeries = new XyScatterRenderableSeries(this.wasmContext, {
                dataSeries: scatterData,
                pointMarker: new EllipsePointMarker(this.wasmContext, {
                    width: POINT_SIZE,
                    height: POINT_SIZE,
                    fill: pathColour,
                    stroke: pathColour,
                    strokeThickness: 0,
                }),
            })

            this.surface.renderableSeries.add(lineSeries)
            this.surface.renderableSeries.add(scatterSeries)

            this.pathLineData.set(path, lineData)
            this.pathScatterData.set(path, scatterData)
            this.pathLineSeries.set(path, lineSeries)
            this.pathScatterSeries.set(path, scatterSeries)
            this.pathPoints.set(path, pts)
        })

        // Highlight always on top
        this.surface.renderableSeries.add(this.highlightSeries!)

        // Arrowheads at the endpoint of each trajectory
        this._addArrowheads(byPath)

        // Feed path -> time[] into hover modifier for tooltip resolution
        const pathTimes = new Map<string, number[]>()
        byPath.forEach((pts, path) => pathTimes.set(path, pts.map(p => p.t)))
        this.hoverModifier.setPathTimes(pathTimes)

        this.surface.zoomExtents()
        console.debug(`[PhaseSpacePanel] setData: ${byPath.size} paths, ${result.n_cells} cells, method=${result.method}`)
    }

    /** Update the current-timepoint highlight: one hollow circle per path nearest to t. */
    setTimepoint(t: number): void {
        if (!this.highlightData) return
        this.highlightData.clear()
        this.pathPoints.forEach(pts => {
            if (pts.length === 0) return
            let nearest = pts[0]!
            let bestDist = Math.abs(nearest.t - t)
            for (let i = 1; i < pts.length; i++) {
                const d = Math.abs(pts[i]!.t - t)
                if (d < bestDist) { bestDist = d; nearest = pts[i]! }
            }
            this.highlightData!.append(nearest.x, nearest.y)
        })
    }

    /** Register a callback fired when the user clicks on a trajectory path. */
    onPathSelect(cb: PathSelectCallback): void {
        this.pathSelectCallback = cb
    }

    /** Register a callback fired on hover (nearest point info) or null on leave. */
    onHover(cb: (info: { t: number; path: string } | null) => void): void {
        this.hoverModifier.onHover(cb)
    }

    override clearData(): void {
        this._clearPathSeries()
        this.result = undefined
        super.clearData()
        this._createHighlightSeries()
    }

    override dispose(): void {
        this._clearPathSeries()
        this.result = undefined
        this.hoverModifier.dispose()
        // Skip clearData()/highlight recreation -- surface.delete() handles full cleanup.
    }

    /** Re-apply theme; update highlight marker stroke colour. */
    override applyTheme(isDark: boolean): void {
        super.applyTheme(isDark)
        if (this.highlightSeries?.pointMarker) {
            this.highlightSeries.pointMarker.stroke = this.theme.text.base
        }
    }

    /** Not applicable for phase-space (no time x-axis). */
    override setTimeExtent(_min: number, _max: number): void {
        // no-op: phase space axes are data-space, not time
    }

    override setVisibleTimeRange(_min: number, _max: number): void {
        // no-op
    }

    // ------------------------------------------------------------------
    // Highlight series
    // ------------------------------------------------------------------

    /** Create the highlight series (hollow circle at current timepoint). */
    private _createHighlightSeries(): void {
        this.highlightData = new XyDataSeries(this.wasmContext, {
            isSorted: false,
            dataSeriesName: "__highlight__",
        })
        this.highlightSeries = new XyScatterRenderableSeries(this.wasmContext, {
            dataSeries: this.highlightData,
            pointMarker: new EllipsePointMarker(this.wasmContext, {
                width: HIGHLIGHT_SIZE,
                height: HIGHLIGHT_SIZE,
                fill: "transparent",
                stroke: this.theme.text.base,
                strokeThickness: 2.5,
            }),
        })
        this.surface.renderableSeries.add(this.highlightSeries)
    }

    // ------------------------------------------------------------------
    // Arrowheads
    // ------------------------------------------------------------------

    /** Place a small SVG arrow at the last point of each path, pointing in the
     *  direction of the final trajectory segment. */
    private _addArrowheads(byPath: Map<string, PhaseSpacePoint[]>): void {
        this._clearArrowheads()
        byPath.forEach((pts) => {
            if (pts.length < 2) return
            const prev = pts[pts.length - 2]!
            const last = pts[pts.length - 1]!
            const dx = last.x - prev.x
            const dy = last.y - prev.y
            if (dx === 0 && dy === 0) return
            // atan2 gives angle from positive x-axis; SVG triangle points right at 0deg
            // Negate dy because data y increases upward but SVG y increases downward
            const angleDeg = Math.atan2(-dy, dx) * (180 / Math.PI) - 90
            const annotation = new CustomAnnotation({
                x1: last.x,
                y1: last.y,
                svgString: arrowSvg(last.colour, angleDeg),
                isEditable: false,
            })
            this.surface.annotations.add(annotation)
            this.arrowAnnotations.push(annotation)
        })
    }

    private _clearArrowheads(): void {
        for (const ann of this.arrowAnnotations) {
            this.surface.annotations.remove(ann)
            ann.delete()
        }
        this.arrowAnnotations = []
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /** Remove and delete all path series (line + scatter). Leaves highlight intact. */
    private _clearPathSeries(): void {
        this._clearArrowheads()
        for (const [path, rs] of this.pathLineSeries) {
            this.surface.renderableSeries.remove(rs)
            rs.delete()
            this.pathLineData.get(path)?.delete()
        }
        for (const [path, rs] of this.pathScatterSeries) {
            this.surface.renderableSeries.remove(rs)
            rs.delete()
            this.pathScatterData.get(path)?.delete()
        }
        this.pathLineSeries.clear()
        this.pathScatterSeries.clear()
        this.pathLineData.clear()
        this.pathScatterData.clear()
        this.pathPoints.clear()
    }
}
