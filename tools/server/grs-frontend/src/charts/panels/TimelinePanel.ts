import {
    AnnotationHoverModifier,
    EAxisAlignment,
    EColumnMode, EColumnYMode, EHorizontalAnchorPoint, EHoverMode, EVerticalAnchorPoint,
    FastRectangleRenderableSeries, LineAnnotation, NumericAxis,
    NumberRange, TextAnnotation, Thickness, XyxyDataSeries,
    type AnnotationBase
} from "scichart"
import { BasePanel, type BasePanelOptions } from "./BasePanel"
import { layoutRectangles, type LayoutRectangle } from "../layout/rectangleLayout"
import type { StructureNode, TimelineSegment } from "@/types/schedule"
import { setSvgAnnotationVisible, setSvgAnnotationsVisible } from "../svgAnnotationVisibility"
import { withOpacity } from "@/utils/colorUtils"
import { CHART_FONT_SIZES, AXIS_THICKNESS } from "../chartConstants"
import { DragGuardModifier } from "../modifiers/DragGuardModifier"

/** Minimum pixel width/height below which a rectangle label is hidden. */
const MIN_LABEL_PX_WIDTH = 80
const MIN_LABEL_PX_HEIGHT = 2

/** Instant model line thickness (normal / hovered). */
const INSTANT_LINE_THICKNESS = 4.0
const INSTANT_LINE_THICKNESS_HOVER = 4.0/** Pixel offset shifting the instant label box right of its line. */
const INSTANT_LABEL_X_SHIFT = 1
/** Rectangle segment fill opacities (mode-independent). */
const RECT_FILL_OPACITY = 0.6
const RECT_FILL_OPACITY_HOVER = 0.8

/** Rectangle segment styling. */
const RECT_STROKE_THICKNESS = 2.0

export type SegmentClickCallback = (segmentId: number, modelPath: string) => void
export type HoverChangeCallback = (modelPath: string | null, executionPath: string | null) => void

export class TimelinePanel extends BasePanel {
    private segmentClickCallback?: SegmentClickCallback
    private hoverChangeCallback?: HoverChangeCallback
    /** Track data annotations so we can clear only them (not modifier-owned ones). */
    private dataAnnotations = new Set<AnnotationBase>()
    /** Currently selected segment ID (null = none). */
    private selectedSegmentId: number | null = null
    /** Full time extent for zoom-to-fit on deselect. */
    private fullTimeExtent: { min: number; max: number } | null = null
    /** Visible range captured just before selection zoom — restored on deselect. */
    private preSelectionTimeRange: { min: number; max: number } | null = null
    /** Stored rectangles for selection lookup. */
    private rectangles: LayoutRectangle[] = []
    /** Currently hovered model path. */
    private currentHoveredModel: string | null = null
    /** Drag guard modifier for click-vs-drag discrimination. */
    private dragGuard: DragGuardModifier | null = null
    /** Reusable tooltip annotation for instant labels (hidden when not hovered). */
    private tooltipAnnotation: TextAnnotation | null = null
    /** Map from rectangle label annotation to its source rectangle (for adaptive visibility). */
    private labelRectMap = new Map<TextAnnotation, LayoutRectangle>()
    /** Map from segmentId to its label annotation (for hover/select colour updates). */
    private segmentLabelMap = new Map<number, TextAnnotation>()
    /** Map from instant label annotation to its slice height in data coords. */
    private instantLabelSliceMap = new Map<TextAnnotation, number>()
    /** Base fill colour for all segment rectangles (theme-aware; updated on theme switch). */
    private segmentColour = ''
    /** Currently selected FastRectangleRenderableSeries. */
    private selectedRectSeries: FastRectangleRenderableSeries | null = null
    private readonly onParentResized = () => requestAnimationFrame(() => this.updateLabelSizes())
    /** True while an instant label is hovered — suppresses rect hover to prevent jitter. */
    private isHoveringInstant = false

    constructor(options: BasePanelOptions) {
        super(options)

        this.dragGuard = this.surface.chartModifiers.asArray()
            .find(m => m instanceof DragGuardModifier) as DragGuardModifier ?? null

        this.surface.chartModifiers.add(new AnnotationHoverModifier({
            enableHover: true,
            hoverMode: EHoverMode.AbsoluteTopmost,
            notifyOutEvent: true,
            notifyPositionUpdate: true,
        }))

        const xAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Time",
            labelStyle: { fontSize: CHART_FONT_SIZES.label },
            axisTitleStyle: { fontSize: CHART_FONT_SIZES.title },
            drawMajorBands: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false
        })

        const yAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Schedule",
            axisAlignment: EAxisAlignment.Left,
            axisTitleStyle: { fontSize: CHART_FONT_SIZES.title },
            drawMajorBands: false,
            drawLabels: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false,
            drawMajorTickLines: false,
            drawMinorTickLines: false,
            axisThickness: AXIS_THICKNESS
        })

        this.surface.xAxes.add(xAxis)
        this.surface.yAxes.add(yAxis)

        xAxis.visibleRangeChanged.subscribe(() => this.updateLabelSizes())
        this.parentSurface.resized.subscribe(this.onParentResized)

        console.debug('[TimelinePanel] Constructed')
    }

    onSegmentClick(callback: SegmentClickCallback): void {
        this.segmentClickCallback = callback
    }

    onHoverChange(callback: HoverChangeCallback): void {
        this.hoverChangeCallback = callback
    }

    override dispose(): void {
        this.parentSurface.resized.unsubscribe(this.onParentResized)
        super.dispose()
    }

    override get isVisible(): boolean {
        return super.isVisible
    }

    /** Hide/show all data annotations when the panel visibility toggles. */
    override set isVisible(value: boolean) {
        console.debug(`[TimelinePanel] isVisible set to ${value}`)
        super.isVisible = value
        this.setAnnotationsVisible(value)
    }

    /** Re-apply theme colours to all annotations, series strokes, and tooltip. */
    override applyTheme(isDark: boolean): void {
        super.applyTheme(isDark)
        const tl = this.theme.timeline
        for (const ann of this.dataAnnotations) {
            if (ann instanceof LineAnnotation) {
                ann.stroke = tl.instant.normal.line
            } else if (ann instanceof TextAnnotation) {
                if (ann.background) {
                    ann.textColor = tl.instant.normal.text
                    ann.background = tl.instant.normal.bg
                } else {
                    ann.textColor = this.theme.text.muted
                }
            }
        }
        if (this.tooltipAnnotation) {
            this.tooltipAnnotation.textColor = this.theme.chart.tooltipFg
            this.tooltipAnnotation.background = this.theme.chart.tooltipBg
        }
        this.segmentColour = tl.rect.colour
        for (const rs of this.surface.renderableSeries.asArray()) {
            if (rs instanceof FastRectangleRenderableSeries) {
                if (rs === this.selectedRectSeries) {
                    rs.fill = withOpacity(tl.rect.selected.fill, RECT_FILL_OPACITY_HOVER)
                    rs.stroke = tl.rect.selected.stroke
                } else {
                    rs.fill = withOpacity(this.segmentColour, RECT_FILL_OPACITY)
                    rs.stroke = tl.rect.normal.stroke
                }
            }
        }
    }

    setScheduleData(structure: StructureNode, segments: TimelineSegment[]): LayoutRectangle[] {
        console.debug(`[TimelinePanel] setScheduleData: ${segments.length} segments`)
        this.clearOwnAnnotations()
        this.tooltipAnnotation = null
        this.labelRectMap.clear()
        this.instantLabelSliceMap.clear()
        this.segmentLabelMap.clear()
        this.surface.renderableSeries.clear()
        this.restoreSelectedSeries()
        this.selectedSegmentId = null
        if (segments.length === 0) { this.rectangles = []; return [] }

        this.rectangles = layoutRectangles(structure, segments, 0, 1)

        const yAxis = this.surface.yAxes.get(0)
        if (yAxis) {
            yAxis.visibleRange = new NumberRange(0, 1)
            yAxis.visibleRangeLimit = new NumberRange(0, 1)
        }

        this.segmentColour = this.theme.timeline.rect.colour
        const instantsByXAndBand = groupInstantsByXAndBand(this.rectangles)

        for (const rect of this.rectangles) {
            if (!rect.isInstant) {
                this.addRectangleSeries(rect)
            }
        }

        for (const [, instants] of instantsByXAndBand) {
            this.addInstantGroup(instants)
        }

        console.debug(`[TimelinePanel] Rendered ${this.rectangles.length} layout items`)
        return this.rectangles
    }

    /** Store full time extent so deselect can zoom back. */
    override setTimeExtent(minTime: number, maxTime: number): void {
        super.setTimeExtent(minTime, maxTime)
        this.fullTimeExtent = { min: minTime, max: maxTime }
    }

    /** Deselect current segment and restore the zoom state that was active before selection. */
    deselectSegment(): void {
        if (this.selectedSegmentId === null) return
        console.debug('[TimelinePanel] Deselecting segment')
        this.restoreSelectedSeries()
        this.selectedSegmentId = null
        const range = this.preSelectionTimeRange ?? this.fullTimeExtent
        if (range) this.setVisibleTimeRange(range.min, range.max)
        this.preSelectionTimeRange = null
        this.segmentClickCallback?.(-1, '')
    }

    /** Whether a segment is currently selected. */
    get hasSegmentSelection(): boolean {
        return this.selectedSegmentId !== null
    }

    // ── Rectangle segments ──────────────────────────────────────────────

    private addRectangleSeries(rect: LayoutRectangle): void {
        const dataSeries = new XyxyDataSeries(this.wasmContext, {
            dataSeriesName: `segment:${rect.segmentId}`,
            isSorted: true,
            containsNaN: false
        })
        dataSeries.appendRange([rect.x1], [rect.y1], [rect.x2], [rect.y2])

        const { segmentId, modelPath, executionPath } = rect

        const rectSeries = new FastRectangleRenderableSeries(this.wasmContext, {
            dataSeries,
            stroke: this.theme.timeline.rect.normal.stroke,
            fill: withOpacity(this.segmentColour, RECT_FILL_OPACITY),
            strokeThickness: RECT_STROKE_THICKNESS,
            columnXMode: EColumnMode.StartEnd,
            columnYMode: EColumnYMode.TopBottom,
            onHoveredChanged: (source) => {
                const hovered = source.isHovered
                const rs = source as FastRectangleRenderableSeries
                // Don't override selection colours on hover
                if (this.selectedSegmentId !== segmentId) {
                    rs.fill = withOpacity(this.segmentColour, hovered ? RECT_FILL_OPACITY_HOVER : RECT_FILL_OPACITY)
                    rs.stroke = hovered ? this.theme.timeline.rect.hover.stroke : this.theme.timeline.rect.normal.stroke
                    const lbl = this.segmentLabelMap.get(segmentId)
                    if (lbl) lbl.textColor = hovered ? this.theme.timeline.rect.hover.text : this.theme.timeline.rect.normal.text
                }
                // Suppress rect hover events while an instant annotation is hovered
                if (this.isHoveringInstant) return
                this.handleHover(hovered, modelPath, executionPath)
            },
            onSelectedChanged: (source) => {
                if (!source.isSelected) return
                // Ignore selection triggered by drag-release
                if (this.dragGuard?.isDrag) {
                    source.isSelected = false
                    return
                }
                source.isSelected = false
                // Toggle: click same segment again -> deselect
                if (this.selectedSegmentId === segmentId) {
                    this.restoreSelectedSeries()
                    this.deselectSegment()
                    return
                }
                // Deselect previous, then highlight new
                this.restoreSelectedSeries()
                const rs = source as FastRectangleRenderableSeries
                this.selectedRectSeries = rs
                rs.fill = withOpacity(this.theme.timeline.rect.selected.fill, RECT_FILL_OPACITY_HOVER)
                rs.stroke = this.theme.timeline.rect.selected.stroke
                rs.strokeThickness = RECT_STROKE_THICKNESS * 1.5
                const lbl = this.segmentLabelMap.get(segmentId)
                if (lbl) lbl.textColor = this.theme.timeline.rect.selected.text

                console.debug(`[TimelinePanel] Segment selected: id=${segmentId} model=${modelPath}`)
                const xRange = this.surface.xAxes.get(0)?.visibleRange
                this.preSelectionTimeRange = xRange ? { min: xRange.min, max: xRange.max } : null
                this.selectedSegmentId = segmentId
                this.zoomToSegment(rect)
                this.segmentClickCallback?.(segmentId, modelPath)
            }
        })

        this.surface.renderableSeries.add(rectSeries)
        this.addRectangleLabel(rect)
    }

    /** Label inside a rectangle segment. Hidden dynamically if it doesn't fit. */
    private addRectangleLabel(rect: LayoutRectangle): void {
        const midX = (rect.x1 + rect.x2) / 2
        const midY = (rect.y1 + rect.y2) / 2
        const fontSize = this.computeLabelFontSize(rect)

        const label = new TextAnnotation({
            x1: midX,
            y1: midY,
            text: rect.executionPath,
            fontSize,
            textColor: this.theme.timeline.rect.normal.text,
            horizontalAnchorPoint: EHorizontalAnchorPoint.Center,
            verticalAnchorPoint: EVerticalAnchorPoint.Center,
            isHidden: !this.labelFits(rect)
        })
        this.addDataAnnotation(label)
        this.labelRectMap.set(label, rect)
        this.segmentLabelMap.set(rect.segmentId, label)
    }

    // ── Instant model groups ────────────────────────────────────────────

    /** Render a group of instant model annotations sharing the same x and y-band. */
    private addInstantGroup(instants: LayoutRectangle[]): void {
        const x = instants[0]!.x1
        const yMin = instants[0]!.y1
        const yMax = instants[0]!.y2

        const line = new LineAnnotation({
            x1: x, x2: x, y1: yMin, y2: yMax,
            stroke: this.theme.timeline.instant.normal.line,
            strokeThickness: INSTANT_LINE_THICKNESS,
        })
        this.addDataAnnotation(line)

        // Divide vertical space equally among labels
        const n = instants.length
        const sliceHeight = (yMax - yMin) / n

        instants.forEach((rect, i) => {
            const sliceTop = yMax - i * sliceHeight
            const sliceBottom = sliceTop - sliceHeight
            const sliceMidY = (sliceTop + sliceBottom) / 2

            this.addInstantLabel(rect, line, x, sliceMidY, sliceHeight)
        })
    }

    /** Single instant label: a TextAnnotation with background fill and hover highlight. */
    private addInstantLabel(
        rect: LayoutRectangle,
        line: LineAnnotation,
        x: number,
        yCenter: number,
        sliceHeight: number
    ): void {
        const { modelPath, executionPath, label } = rect
        const tooltipText = `${label}\nPath: ${executionPath}\nModel: ${modelPath}`
        const fontSize = this.computeInstantFontSize(sliceHeight)

        const text = new TextAnnotation({
            x1: x,
            y1: yCenter,
            text: executionPath,
            fontSize,
            textColor: this.theme.timeline.instant.normal.text,
            background: this.theme.timeline.instant.normal.bg,
            horizontalAnchorPoint: EHorizontalAnchorPoint.Left,
            verticalAnchorPoint: EVerticalAnchorPoint.Center,
            xCoordShift: INSTANT_LABEL_X_SHIFT,
            padding: new Thickness(3, 6, 3, 9),
            onHover: (args) => {
                const hovered = args.isHovered
                console.debug(`[TimelinePanel] Instant label hover: hovered=${hovered} model=${modelPath}`)
                // Batch all property mutations to prevent rendering artefacts
                this.surface.suspendUpdates()
                line.stroke = hovered ? this.theme.timeline.instant.hover.line : this.theme.timeline.instant.normal.line
                line.strokeThickness = hovered ? INSTANT_LINE_THICKNESS_HOVER : INSTANT_LINE_THICKNESS
                text.background = hovered ? this.theme.timeline.instant.hover.bg : this.theme.timeline.instant.normal.bg
                text.textColor = hovered ? this.theme.timeline.instant.hover.text : this.theme.timeline.instant.normal.text
                if (hovered) {
                    const xOffset = this.computeTooltipXOffset()
                    this.showTooltipAt(x + xOffset, yCenter - sliceHeight / 2, tooltipText)
                } else {
                    this.hideTooltipAnnotation()
                }
                this.surface.resumeUpdates()
                this.isHoveringInstant = hovered
                this.handleHover(hovered, modelPath, executionPath)
            },
        })
        this.addDataAnnotation(text)
        this.instantLabelSliceMap.set(text, sliceHeight)
    }

    // ── Hover handling ──────────────────────────────────────────────────

    /** Unified hover handler for both rectangles and instant labels. */
    private handleHover(hovered: boolean, modelPath: string, executionPath: string): void {
        if (hovered) {
            this.currentHoveredModel = modelPath
            console.debug(`[TimelinePanel] Hover enter: model=${modelPath} path=${executionPath}`)
            this.hoverChangeCallback?.(modelPath, executionPath)
        } else {
            console.debug(`[TimelinePanel] Hover leave: model=${this.currentHoveredModel}`)
            this.currentHoveredModel = null
            this.hoverChangeCallback?.(null, null)
        }
    }

    // ── Tooltip annotation ──────────────────────────────────────────────

    /** Show a tooltip annotation at the given data coordinates. */
    private showTooltipAt(x: number, y: number, text: string): void {
        if (!this.tooltipAnnotation) {
            this.tooltipAnnotation = new TextAnnotation({
                x1: x,
                y1: y,
                text,
                fontSize: 10,
                textColor: this.theme.chart.tooltipFg,
                background: this.theme.chart.tooltipBg,
                horizontalAnchorPoint: EHorizontalAnchorPoint.Left,
                verticalAnchorPoint: EVerticalAnchorPoint.Bottom,
                padding: new Thickness(4, 8, 4, 8),
                isHidden: false,
            })
            this.surface.annotations.add(this.tooltipAnnotation)
        } else {
            this.tooltipAnnotation.x1 = x
            this.tooltipAnnotation.y1 = y
            this.tooltipAnnotation.text = text
            this.tooltipAnnotation.isHidden = false
        }
    }

    /** Hide the tooltip annotation. */
    private hideTooltipAnnotation(): void {
        if (this.tooltipAnnotation) {
            this.tooltipAnnotation.isHidden = true
        }
    }

    // ── Selection / Zoom ────────────────────────────────────────────────

    /** Zoom x-axis to fit a segment (with a small margin). */
    private zoomToSegment(rect: LayoutRectangle): void {
        const xAxis = this.surface.xAxes.get(0)
        if (xAxis) {
            xAxis.visibleRange = new NumberRange(rect.x1, rect.x2)
        }
    }

    // ── Label sizing helpers ────────────────────────────────────────────

    /**
     * Recompute font sizes and visibility for all rectangle and instant labels.
     * Triggered by both x-axis zoom and parent surface resize.
     */
    private updateLabelSizes(): void {
        if (!this.isVisible) return
        const h = this.subchartHeightPx()
        if (h === 0) return
        for (const [label, rect] of this.labelRectMap) {
            const fits = this.labelFits(rect)
            label.isHidden = !fits
            if (fits) {
                label.fontSize = this.computeLabelFontSize(rect)
            }
        }
        for (const [label, sliceHeight] of this.instantLabelSliceMap) {
            label.fontSize = this.computeInstantFontSize(sliceHeight)
        }
    }

    /**
     * Toggle annotations hidden/visible when panel visibility changes.
     * Uses direct SVG DOM manipulation — see svgAnnotationVisibility.ts.
     */
    private setAnnotationsVisible(visible: boolean): void {
        setSvgAnnotationsVisible(this.dataAnnotations, visible)
        if (this.tooltipAnnotation) {
            setSvgAnnotationVisible(this.tooltipAnnotation, false)
        }
        // Also hide/show renderable series (rectangles) via opacity
        for (const rs of this.surface.renderableSeries.asArray()) {
            rs.opacity = visible ? 1 : 0
        }
    }

    /** Restore the previously selected rectangle to its normal style. */
    private restoreSelectedSeries(): void {
        if (this.selectedRectSeries) {
            this.selectedRectSeries.fill = withOpacity(this.segmentColour, RECT_FILL_OPACITY)
            this.selectedRectSeries.stroke = this.theme.timeline.rect.normal.stroke
            this.selectedRectSeries.strokeThickness = RECT_STROKE_THICKNESS
        }
        // Restore label colour on the previously selected segment
        if (this.selectedSegmentId !== null) {
            const lbl = this.segmentLabelMap.get(this.selectedSegmentId)
            if (lbl) lbl.textColor = this.theme.timeline.rect.normal.text
        }
        this.selectedRectSeries = null
    }

    /** Pixel height of this subchart, or 0 if not yet laid out. */
    private subchartHeightPx(): number {
        try { return this.surface.getSubChartRect().height } catch { return 0 }
    }

    /** Pixel width of this subchart, or 0 if not yet laid out. */
    private subchartWidthPx(): number {
        try { return this.surface.getSubChartRect().width } catch { return 0 }
    }

    /** X-axis offset for tooltip positioning (1% of current visible range). */
    private computeTooltipXOffset(): number {
        const xRange = this.surface.xAxes.get(0)?.visibleRange
        return xRange ? (xRange.max - xRange.min) * 0.01 : 0
    }

    /** Compute font size relative to the rectangle's estimated pixel height. */
    private computeLabelFontSize(rect: LayoutRectangle): number {
        const yAxis = this.surface.yAxes.get(0)
        if (!yAxis) return 6
        const yRange = yAxis.visibleRange
        const pxPerUnitY = this.subchartHeightPx() / (yRange.max - yRange.min)
        const rectPxHeight = (rect.y2 - rect.y1) * pxPerUnitY
        return Math.round(Math.max(6, Math.min(12, rectPxHeight * 0.35)))
    }

    /** Whether a text label fits inside a rectangle at the current zoom. */
    private labelFits(rect: LayoutRectangle): boolean {
        const xAxis = this.surface.xAxes.get(0)
        const yAxis = this.surface.yAxes.get(0)
        if (!xAxis || !yAxis) return true
        const xRange = xAxis.visibleRange
        const yRange = yAxis.visibleRange
        const pxPerUnitX = this.subchartWidthPx() / (xRange.max - xRange.min)
        const pxPerUnitY = this.subchartHeightPx() / (yRange.max - yRange.min)
        const rectPxWidth = (rect.x2 - rect.x1) * pxPerUnitX
        const rectPxHeight = (rect.y2 - rect.y1) * pxPerUnitY
        return rectPxWidth >= MIN_LABEL_PX_WIDTH && rectPxHeight >= MIN_LABEL_PX_HEIGHT
    }

    /** Compute font size for instant labels relative to their vertical slice. */
    private computeInstantFontSize(sliceHeight: number): number {
        const slicePx = sliceHeight * this.subchartHeightPx()
        return Math.round(Math.max(6, Math.min(11, slicePx * 0.03)))
    }

    // ── Annotation lifecycle ────────────────────────────────────────────

    private addDataAnnotation(ann: AnnotationBase): void {
        this.surface.annotations.add(ann)
        this.dataAnnotations.add(ann)
    }

    private clearOwnAnnotations(): void {
        for (const ann of this.dataAnnotations) {
            this.surface.annotations.remove(ann)
            ann.delete()
        }
        this.dataAnnotations.clear()
    }
}

// ── Pure helpers ─────────────────────────────────────────────────────────

/** Group instants by (x, y-band) so branches get separate lines. */
function groupInstantsByXAndBand(rectangles: LayoutRectangle[]): Map<string, LayoutRectangle[]> {
    const map = new Map<string, LayoutRectangle[]>()
    for (const rect of rectangles) {
        if (!rect.isInstant) continue
        const key = `${rect.x1}:${rect.y1}:${rect.y2}`
        const list = map.get(key)
        if (list) { list.push(rect) }
        else { map.set(key, [rect]) }
    }
    return map
}