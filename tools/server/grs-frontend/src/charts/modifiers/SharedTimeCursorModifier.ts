import { ChartModifierBase2D, DpiHelper, EChart2DModifierType, ECoordinateMode, EHorizontalAnchorPoint, EVerticalAnchorPoint, LineAnnotation, ModifierMouseArgs, Point, TextAnnotation, Thickness, translateFromCanvasToSeriesViewRect, translateToNotScaled, type ISciChartSubSurface } from "scichart"




export class SharedTimeCursorModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private xLines = new Map<string, LineAnnotation>()
    private timeLabels = new Map<string, TextAnnotation>()
    private color: string
    private onTimeChanged?: (t: number) => void

    constructor(callback?: (t: number) => void, color="#1f1f1f") {
        super()
        this.onTimeChanged = callback
        this.color = color
    }



    onAttachSubSurface(subChart: ISciChartSubSurface): void {
        const line = new LineAnnotation({
            xCoordinateMode: ECoordinateMode.Pixel,
            yCoordinateMode: ECoordinateMode.Pixel,
            stroke: this.color,
            strokeThickness: 1,
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
            background: this.color,
            opacity: 1.0,
            padding: new Thickness(3,2,3,2),
            isHidden: true
        })

        subChart.annotations.add(label)
        this.timeLabels.set(subChart.id, label)
    
    }

    onDetachSubSurface(subChart: ISciChartSubSurface): void {
        const l = this.xLines.get(subChart.id)
        l?.delete()
        subChart.annotations.remove(l!)
        this.xLines.delete(subChart.id)
    }

    modifierMouseMove(args: ModifierMouseArgs): void {
        super.modifierMouseMove(args)
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

        const xPix = translateToNotScaled(translatedPt.x)
        this.parentSurface.subCharts.forEach(sc => {
            const rect = sc.seriesViewRect
            if (!rect) return

            const line = this.xLines.get(sc.id)
            line!.isHidden = false
            line!.x1 = xPix
            line!.x2 = xPix
            line!.y1 = 0
            line!.y2 = rect.bottom / DpiHelper.PIXEL_RATIO
            
            // add time label on last subchart
            if (sc === lastVisibleChart) {
                const label = this.timeLabels.get(sc.id)
                label!.isHidden = false
                label!.x1 = time
                label!.text = time.toFixed(2)
            }
        });

    }

    modifierMouseLeave(_: ModifierMouseArgs): void {
        this.timeLabels.forEach(l => l.isHidden = true)
        this.xLines.forEach(l => l.isHidden = true)
    }

}