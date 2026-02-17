import {
    EAxisAlignment, ECoordinateMode, EHorizontalAnchorPoint, EVerticalAnchorPoint,
    FastRectangleRenderableSeries, LineAnnotation, NumericAxis,
    NumberRange, TextAnnotation, Thickness, XyxyDataSeries
} from "scichart"
import { BasePanel, type BasePanelOptions } from "./BasePanel"
import { layoutRectangles, type LayoutRectangle } from "../layout/rectangleLayout"
import type { StructureNode, TimelineSegment } from "@/types/schedule"
import { darken, withOpacity } from "@/utils/colorUtils"
import { CHART_FONT_FAMILY, CHART_FONT_SIZES, AXIS_THICKNESS, SEGMENT_PALETTE } from "../chartConstants"

const SEGMENT_LABEL_FONT_SIZE = 7
const SEGMENT_BORDER_THICKNESS = 2

export type SegmentClickCallback = (segmentId: number, modelPath: string) => void

export class TimelinePanel extends BasePanel {
    private segmentClickCallback?: SegmentClickCallback
    private hoverTooltip!: TextAnnotation
    /** Track data annotations so we can clear only them (not modifier-owned ones). */
    private dataAnnotations: Set<LineAnnotation | TextAnnotation> = new Set()

    constructor(options: BasePanelOptions) {
        super(options)

        const xAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Time",
            labelStyle: { fontSize: CHART_FONT_SIZES.label },
            axisTitleStyle: { fontSize: CHART_FONT_SIZES.title, fontFamily: CHART_FONT_FAMILY },
            drawMajorBands: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false
        })

        const yAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Schedule Timeline",
            axisAlignment: EAxisAlignment.Left,
            axisTitleStyle: { fontSize: CHART_FONT_SIZES.title, fontFamily: CHART_FONT_FAMILY },
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

        this.createHoverTooltip()
    }

    onSegmentClick(callback: SegmentClickCallback): void {
        this.segmentClickCallback = callback
    }

    setScheduleData(structure: StructureNode, segments: TimelineSegment[]): LayoutRectangle[] {
        this.surface.renderableSeries.clear()
        // Clear only our own data annotations, not modifier-owned cursor annotations
        for (const ann of this.dataAnnotations) {
            this.surface.annotations.remove(ann)
            ann.delete()
        }
        this.dataAnnotations.clear()
        // Recreate tooltip (old one was deleted)
        this.createHoverTooltip()
        if (segments.length === 0) return []


        const rectangles = layoutRectangles(structure, segments, 0, 1)
        console.debug(`[TimelinePanel] setScheduleData: ${segments.length} segments -> ${rectangles.length} rectangles`)

        const yAxis = this.surface.yAxes.get(0)
        if (yAxis) {
            yAxis.visibleRange = new NumberRange(0, 1)
            yAxis.visibleRangeLimit = new NumberRange(0, 1)
        }

        const palette = buildSegmentPalette(rectangles)

        // Collect instants grouped by x position for vertical label stacking
        const instantsByX = new Map<number, LayoutRectangle[]>()

        for (const rect of rectangles) {
            if (rect.isInstant) {
                const list = instantsByX.get(rect.x1)
                if (list) {
                    list.push(rect)
                } else {
                    instantsByX.set(rect.x1, [rect])
                }
            } else {
                this.addRectangleSeries(rect, palette.get(rect.segmentId)!)
            }
        }

        // Add instant annotations with stacked labels
        for (const [, instants] of instantsByX) {
            this.addInstantGroup(instants)
        }

        return rectangles
    }

    private addRectangleSeries(rect: LayoutRectangle, colour: string): void {
        const dataSeries = new XyxyDataSeries(this.wasmContext, {
            dataSeriesName: `segment:${rect.segmentId}`,
            isSorted: true,
            containsNaN: false
        })
        dataSeries.appendRange([rect.x1], [rect.y1], [rect.x2], [rect.y2])

        const segmentId = rect.segmentId
        const modelPath = rect.modelPath
        const tooltipText = `${rect.label}\nPath: ${rect.executionPath}\nModel: ${modelPath}`
        const tooltip = this.hoverTooltip
        const midX = (rect.x1 + rect.x2) / 2
        const topY = rect.y1

        const rectSeries = new FastRectangleRenderableSeries(this.wasmContext, {
            dataSeries,
            fill: withOpacity(colour, 0.6),
            stroke: darken(colour),
            strokeThickness: SEGMENT_BORDER_THICKNESS,
            onHoveredChanged: (sourceSeries) => {
                ;(sourceSeries as FastRectangleRenderableSeries).fill =
                    sourceSeries.isHovered ? withOpacity(colour, 0.8) : withOpacity(colour, 0.6)
                if (sourceSeries.isHovered) {
                    tooltip.x1 = midX
                    tooltip.y1 = topY
                    tooltip.text = tooltipText
                    tooltip.isHidden = false
                } else {
                    tooltip.isHidden = true
                }
            },
            onSelectedChanged: (sourceSeries) => {
                if (sourceSeries.isSelected) {
                    console.debug(`[TimelinePanel] Segment clicked: id=${segmentId} modelPath=${modelPath}`)
                    this.segmentClickCallback?.(segmentId, modelPath)
                }
            }
        })

        this.surface.renderableSeries.add(rectSeries)

        // Path-only label inside the rectangle
        const labelMidY = (rect.y1 + rect.y2) / 2
        const label = new TextAnnotation({
            x1: midX,
            y1: labelMidY,
            text: rect.executionPath,
            fontSize: SEGMENT_LABEL_FONT_SIZE,
            fontFamily: CHART_FONT_FAMILY,
            textColor: "#555555",
            horizontalAnchorPoint: EHorizontalAnchorPoint.Center,
            verticalAnchorPoint: EVerticalAnchorPoint.Center
        })
        this.surface.annotations.add(label)
        this.dataAnnotations.add(label)
    }

    /** Create a fresh hover tooltip annotation and add it to the surface. */
    private createHoverTooltip(): void {
        this.hoverTooltip = new TextAnnotation({
            xCoordinateMode: ECoordinateMode.DataValue,
            yCoordinateMode: ECoordinateMode.DataValue,
            x1: 0,
            y1: 0,
            text: "",
            fontSize: CHART_FONT_SIZES.annotation,
            fontFamily: CHART_FONT_FAMILY,
            textColor: "#FFFFFF",
            background: "#333333",
            padding: new Thickness(4, 3, 4, 3),
            horizontalAnchorPoint: EHorizontalAnchorPoint.Left,
            verticalAnchorPoint: EVerticalAnchorPoint.Bottom,
            isHidden: true
        })
        this.surface.annotations.add(this.hoverTooltip)
        this.dataAnnotations.add(this.hoverTooltip)
    }

    /** Render a group of instant annotations at the same x, with vertically stacked labels. */
    private addInstantGroup(instants: LayoutRectangle[]): void {
        // Use the full y-span across all instants at this x
        const yMin = Math.min(...instants.map(r => r.y1))
        const yMax = Math.max(...instants.map(r => r.y2))

        const line = new LineAnnotation({
            x1: instants[0]!.x1,
            x2: instants[0]!.x1,
            y1: yMin,
            y2: yMax,
            stroke: "#666666",
            strokeThickness: 1,
            strokeDashArray: [4, 2]
        })
        this.surface.annotations.add(line)
        this.dataAnnotations.add(line)

        // Stack horizontal labels vertically downward from the top
        const labelHeight = 0.04
        const startY = yMax - 0.04

        instants.forEach((rect, i) => {
            const label = new TextAnnotation({
                x1: rect.x1,
                y1: startY + i * labelHeight,
                text: rect.executionPath,
                fontSize: SEGMENT_LABEL_FONT_SIZE,
                fontFamily: CHART_FONT_FAMILY,
                textColor: "#666666",
                horizontalAnchorPoint: EHorizontalAnchorPoint.Left,
                verticalAnchorPoint: EVerticalAnchorPoint.Top
            })
            this.surface.annotations.add(label)
            this.dataAnnotations.add(label)
        })
    }
}

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