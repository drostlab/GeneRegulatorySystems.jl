import { ChartModifierBase2D, DpiHelper, EChart2DModifierType, ECoordinateMode, EHorizontalAnchorPoint, EVerticalAnchorPoint, LineAnnotation, ModifierMouseArgs, Point, TextAnnotation, Thickness, translateFromCanvasToSeriesViewRect, type ISciChartSubSurface } from "scichart"


/** Colour for the time cursor line and label. */
const CURSOR_COLOUR = "#666666"


export class SharedTimeCursorModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private xLines = new Map<string, LineAnnotation>()
    private timeLabels = new Map<string, TextAnnotation>()
    private onTimeChanged?: (t: number) => void

    constructor(callback?: (t: number) => void) {
        super()
        this.onTimeChanged = callback
    }



    onAttachSubSurface(subChart: ISciChartSubSurface): void {
        console.debug(`[TimeCursor] onAttachSubSurface: id=${subChart.id}, isVisible=${subChart.isVisible}`)
        const line = new LineAnnotation({
            xCoordinateMode: ECoordinateMode.DataValue,
            yCoordinateMode: ECoordinateMode.Pixel,
            stroke: CURSOR_COLOUR,
            strokeThickness: 3,
            isHidden: true
        })
        subChart.annotations.add(line)
        this.xLines.set(subChart.id, line)

        const label = new TextAnnotation({
            xCoordinateMode: ECoordinateMode.DataValue,
            yCoordinateMode: ECoordinateMode.Relative,
            y1: 1.0,
            verticalAnchorPoint: EVerticalAnchorPoint.Bottom,
            horizontalAnchorPoint: EHorizontalAnchorPoint.Center,
            fontSize: 8,
            textColor: "#FFFFFF",
            background: CURSOR_COLOUR,
            opacity: 1.0,
            padding: new Thickness(3,2,3,2),
            isHidden: true
        })

        subChart.annotations.add(label)
        this.timeLabels.set(subChart.id, label)
    
    }

    onDetachSubSurface(subChart: ISciChartSubSurface): void {
        const line = this.xLines.get(subChart.id)
        if (line) {
            subChart.annotations.remove(line)
            line.delete()
            this.xLines.delete(subChart.id)
        }
        const label = this.timeLabels.get(subChart.id)
        if (label) {
            subChart.annotations.remove(label)
            label.delete()
            this.timeLabels.delete(subChart.id)
        }
    }

    modifierMouseMove(args: ModifierMouseArgs): void {
        super.modifierMouseMove(args)
        this._updateCursorFromMouse()
    }

    modifierMouseDown(args: ModifierMouseArgs): void {
        super.modifierMouseDown(args)
        this._updateCursorFromMouse()
    }

    /** Translate current mouse position to data time and update all cursor lines. */
    private _updateCursorFromMouse(): void {
        if (!this.mousePoint) return

        let activeSubChart: ISciChartSubSurface | undefined
        let translatedPt: Point | undefined

        this.parentSurface.subCharts.forEach(sc => {
            const pt = translateFromCanvasToSeriesViewRect(this.mousePoint!, sc.seriesViewRect)
            if (pt) {
                activeSubChart = sc
                translatedPt = pt
            }
        })

        if (!activeSubChart || !translatedPt) return

        const xAxis = activeSubChart.xAxes.get(0)
        const calc = xAxis.getCurrentCoordinateCalculator()
        const time = calc.getDataValue(translatedPt.x)
        if (time !== undefined) this.onTimeChanged?.(time)

        const lastVisibleChart = [...this.parentSurface.subCharts].reverse().find(sc => sc.isVisible)

        this.parentSurface.subCharts.forEach(sc => {
            const rect = sc.seriesViewRect
            if (!rect) return

            const line = this.xLines.get(sc.id)
            if (!line) return
            line.isHidden = false
            line.x1 = time
            line.x2 = time
            line.y1 = 0
            line.y2 = rect.bottom / DpiHelper.PIXEL_RATIO

            // Add time label on last subchart only
            if (sc === lastVisibleChart) {
                const label = this.timeLabels.get(sc.id)
                if (label) {
                    label.isHidden = false
                    label.x1 = time
                    label.text = time.toFixed(2)
                }
            }
        })
    }

    modifierMouseLeave(_: ModifierMouseArgs): void {
        // Cursor stays visible at last position
    }

}