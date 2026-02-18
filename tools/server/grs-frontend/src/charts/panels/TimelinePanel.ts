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
import { withOpacity } from "@/utils/colorUtils"
import { CHART_FONT_SIZES, AXIS_THICKNESS, SEGMENT_PALETTE } from "../chartConstants"
import { DragGuardModifier } from "../modifiers/DragGuardModifier"

/** Minimum pixel width/height below which a rectangle label is hidden. */
const MIN_LABEL_PX_WIDTH = 30
const MIN_LABEL_PX_HEIGHT = 10

/** Instant model styling. */
const INSTANT_LINE_COLOUR = "#888888"
const INSTANT_LINE_COLOUR_HOVER = "#444444"
const INSTANT_BG_COLOUR = "#f0f0f0"
const INSTANT_BG_COLOUR_HOVER = "#dceaff"
const INSTANT_TEXT_COLOUR = "#555555"
const INSTANT_LINE_THICKNESS = 1
const INSTANT_LINE_THICKNESS_HOVER = 2.5

/** Rectangle segment styling. */
const RECT_STROKE_COLOUR = "gray"
const RECT_STROKE_THICKNESS = 2.0
const RECT_OPACITY_NORMAL = 0.6
const RECT_OPACITY_HOVER = 0.85

export type SegmentClickCallback = (segmentId: number, modelPath: string) => void
export type HoverChangeCallback = (modelPath: string | null) => void

export class TimelinePanel extends BasePanel {
    private segmentClickCallback?: SegmentClickCallback
    private hoverChangeCallback?: HoverChangeCallback
    /** Track data annotations so we can clear only them (not modifier-owned ones). */
    private dataAnnotations = new Set<AnnotationBase>()
    /** Currently selected segment ID (null = none). */
    private selectedSegmentId: number | null = null
    /** Full time extent for zoom-to-fit on deselect. */
    private fullTimeExtent: { min: number; max: number } | null = null
    /** Stored rectangles for selection lookup. */
    private rectangles: LayoutRectangle[] = []
    /** Currently hovered model path. */
    private currentHoveredModel: string | null = null
    /** Drag guard modifier for click-vs-drag discrimination. */
    private dragGuard: DragGuardModifier | null = null
    /** Reusable tooltip annotation for instant labels (hidden when not hovered). */
    private tooltipAnnotation: TextAnnotation | null = null

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
            axisTitle: "Schedule Timeline",
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

        console.debug('[TimelinePanel] Constructed')
    }

    onSegmentClick(callback: SegmentClickCallback): void {
        this.segmentClickCallback = callback
    }

    onHoverChange(callback: HoverChangeCallback): void {
        this.hoverChangeCallback = callback
    }

    setScheduleData(structure: StructureNode, segments: TimelineSegment[]): LayoutRectangle[] {
        console.debug(`[TimelinePanel] setScheduleData: ${segments.length} segments`)
        this.clearOwnAnnotations()
        this.tooltipAnnotation = null
        this.surface.renderableSeries.clear()
        this.selectedSegmentId = null
        if (segments.length === 0) { this.rectangles = []; return [] }

        this.rectangles = layoutRectangles(structure, segments, 0, 1)

        const yAxis = this.surface.yAxes.get(0)
        if (yAxis) {
            yAxis.visibleRange = new NumberRange(0, 1)
            yAxis.visibleRangeLimit = new NumberRange(0, 1)
        }

        const palette = buildSegmentPalette(this.rectangles)
        const instantsByX = groupInstantsByX(this.rectangles)

        for (const rect of this.rectangles) {
            if (!rect.isInstant) {
                this.addRectangleSeries(rect, palette.get(rect.segmentId)!)
            }
        }

        for (const [, instants] of instantsByX) {
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

    /** Deselect current segment and zoom back to full extent. */
    deselectSegment(): void {
        if (this.selectedSegmentId === null) return
        console.debug('[TimelinePanel] Deselecting segment')
        this.selectedSegmentId = null
        if (this.fullTimeExtent) {
            this.setVisibleTimeRange(this.fullTimeExtent.min, this.fullTimeExtent.max)
        }
        this.segmentClickCallback?.(-1, '')
    }

    /** Whether a segment is currently selected. */
    get hasSegmentSelection(): boolean {
        return this.selectedSegmentId !== null
    }

    // ── Rectangle segments ──────────────────────────────────────────────

    private addRectangleSeries(rect: LayoutRectangle, colour: string): void {
        const dataSeries = new XyxyDataSeries(this.wasmContext, {
            dataSeriesName: `segment:${rect.segmentId}`,
            isSorted: true,
            containsNaN: false
        })
        dataSeries.appendRange([rect.x1], [rect.y1], [rect.x2], [rect.y2])

        const { segmentId, modelPath } = rect

        const rectSeries = new FastRectangleRenderableSeries(this.wasmContext, {
            dataSeries,
            stroke: RECT_STROKE_COLOUR,
            fill: withOpacity(colour, RECT_OPACITY_NORMAL),
            strokeThickness: RECT_STROKE_THICKNESS,
            columnXMode: EColumnMode.StartEnd,
            columnYMode: EColumnYMode.TopBottom,
            onHoveredChanged: (source) => {
                const hovered = source.isHovered
                const rs = source as FastRectangleRenderableSeries
                rs.fill = withOpacity(colour, hovered ? RECT_OPACITY_HOVER : RECT_OPACITY_NORMAL)
                this.handleHover(hovered, modelPath)
            },
            onSelectedChanged: (source) => {
                if (!source.isSelected) return
                // Ignore selection triggered by drag-release
                if (this.dragGuard?.isDrag) {
                    source.isSelected = false
                    return
                }
                // Toggle: click same segment again -> deselect
                if (this.selectedSegmentId === segmentId) {
                    source.isSelected = false
                    this.deselectSegment()
                    return
                }
                console.debug(`[TimelinePanel] Segment selected: id=${segmentId} model=${modelPath}`)
                this.selectedSegmentId = segmentId
                this.zoomToSegment(rect)
                this.segmentClickCallback?.(segmentId, modelPath)
                source.isSelected = false
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
            textColor: "#555555",
            horizontalAnchorPoint: EHorizontalAnchorPoint.Center,
            verticalAnchorPoint: EVerticalAnchorPoint.Center,
            isHidden: !this.labelFits(rect)
        })
        this.addDataAnnotation(label)
    }

    // ── Instant model groups ────────────────────────────────────────────

    /** Render a group of instant model annotations at the same x coordinate. */
    private addInstantGroup(instants: LayoutRectangle[]): void {
        const x = instants[0]!.x1
        const yMin = Math.min(...instants.map(r => r.y1))
        const yMax = Math.max(...instants.map(r => r.y2))

        const line = new LineAnnotation({
            x1: x, x2: x, y1: yMin, y2: yMax,
            stroke: INSTANT_LINE_COLOUR,
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
            textColor: INSTANT_TEXT_COLOUR,
            background: INSTANT_BG_COLOUR,
            horizontalAnchorPoint: EHorizontalAnchorPoint.Left,
            verticalAnchorPoint: EVerticalAnchorPoint.Center,
            padding: new Thickness(3, 6, 3, 6),
            onHover: (args) => {
                const hovered = args.isHovered
                console.debug(`[TimelinePanel] Instant label hover: hovered=${hovered} model=${modelPath}`)
                line.stroke = hovered ? INSTANT_LINE_COLOUR_HOVER : INSTANT_LINE_COLOUR
                line.strokeThickness = hovered ? INSTANT_LINE_THICKNESS_HOVER : INSTANT_LINE_THICKNESS
                text.background = hovered ? INSTANT_BG_COLOUR_HOVER : INSTANT_BG_COLOUR
                text.textColor = hovered ? "#333333" : INSTANT_TEXT_COLOUR
                if (hovered) {
                    this.showTooltipAt(x, yCenter - sliceHeight / 2, tooltipText)
                } else {
                    this.hideTooltipAnnotation()
                }
                this.handleHover(hovered, modelPath)
            },
        })
        this.addDataAnnotation(text)
    }

    // ── Hover handling ──────────────────────────────────────────────────

    /** Unified hover handler for both rectangles and instant labels. */
    private handleHover(hovered: boolean, modelPath: string): void {
        if (hovered) {
            this.currentHoveredModel = modelPath
            console.debug(`[TimelinePanel] Hover enter: model=${modelPath}`)
            this.hoverChangeCallback?.(modelPath)
        } else {
            console.debug(`[TimelinePanel] Hover leave: model=${this.currentHoveredModel}`)
            this.currentHoveredModel = null
            this.hoverChangeCallback?.(null)
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
                textColor: '#ffffff',
                background: '#333333',
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
        const margin = (rect.x2 - rect.x1) * 0.05
        const xAxis = this.surface.xAxes.get(0)
        if (xAxis) {
            xAxis.visibleRange = new NumberRange(rect.x1 - margin, rect.x2 + margin)
        }
    }

    // ── Label sizing helpers ────────────────────────────────────────────

    /** Compute font size relative to the rectangle's estimated pixel height. */
    private computeLabelFontSize(rect: LayoutRectangle): number {
        const chartHeight = this.surface.renderSurface?.viewportSize?.height ?? 200
        const rectPxHeight = (rect.y2 - rect.y1) * chartHeight
        return Math.max(6, Math.min(12, rectPxHeight * 0.35))
    }

    /** Whether a text label fits inside a rectangle at the current zoom. */
    private labelFits(rect: LayoutRectangle): boolean {
        const chartWidth = this.surface.renderSurface?.viewportSize?.width ?? 400
        const chartHeight = this.surface.renderSurface?.viewportSize?.height ?? 200
        const xAxis = this.surface.xAxes.get(0)
        if (!xAxis) return true
        const range = xAxis.visibleRange
        const pxPerUnit = chartWidth / (range.max - range.min)
        const rectPxWidth = (rect.x2 - rect.x1) * pxPerUnit
        const rectPxHeight = (rect.y2 - rect.y1) * chartHeight
        return rectPxWidth >= MIN_LABEL_PX_WIDTH && rectPxHeight >= MIN_LABEL_PX_HEIGHT
    }

    /** Compute font size for instant labels relative to their vertical slice. */
    private computeInstantFontSize(sliceHeight: number): number {
        const chartHeight = this.surface.renderSurface?.viewportSize?.height ?? 200
        const slicePx = sliceHeight * chartHeight
        return Math.max(6, Math.min(11, slicePx * 0.3))
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

function buildSegmentPalette(rectangles: LayoutRectangle[]): Map<number, string> {
    const palette = new Map<number, string>()
    const pathColours = new Map<string, string>()
    let colourIndex = 0

    for (const rect of rectangles) {
        if (rect.isInstant || palette.has(rect.segmentId)) continue
        let colour = pathColours.get(rect.modelPath)
        if (!colour) {
            colour = SEGMENT_PALETTE[colourIndex % SEGMENT_PALETTE.length]!
            pathColours.set(rect.modelPath, colour)
            colourIndex++
        }
        palette.set(rect.segmentId, colour)
    }
    return palette
}

function groupInstantsByX(rectangles: LayoutRectangle[]): Map<number, LayoutRectangle[]> {
    const map = new Map<number, LayoutRectangle[]>()
    for (const rect of rectangles) {
        if (!rect.isInstant) continue
        const list = map.get(rect.x1)
        if (list) { list.push(rect) }
        else { map.set(rect.x1, [rect]) }
    }
    return map
}