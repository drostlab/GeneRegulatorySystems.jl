import { AxisBase2D, ChartModifierBase2D, EChart2DModifierType, NumberRange} from "scichart";


export class AxisSyncModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private visibleRangeLimit?: NumberRange

   onAttach() {
        if (!this.parentSurface) return
        this.parentSurface.subCharts.forEach(sc => 
            sc.xAxes.asArray().forEach(xAxis => this.attachAxis(xAxis))
        )
    }
    attachAxis(xAxis: AxisBase2D) {
        if (this.visibleRangeLimit)
            xAxis.visibleRangeLimit = this.visibleRangeLimit

        xAxis.visibleRangeChanged.subscribe(args => {
            if (!args?.visibleRange) return
            const { visibleRange } = args
            this.parentSurface!.subCharts.forEach(sc =>
                sc.xAxes.asArray().forEach(ax => {
                    if (ax != xAxis) {
                        const vr = ax.visibleRange
                        if (!vr || vr.min !== visibleRange.min || vr.max !== visibleRange.max) {
                            ax.visibleRange = visibleRange
                        }
                    }
                })
            )
        })
        
    }
    setVisibleRangeLimit(limit: NumberRange) {
        this.visibleRangeLimit = limit
        this.parentSurface?.subCharts.forEach(sc =>
            sc.xAxes.asArray().forEach(ax => (ax.visibleRangeLimit = limit))
        )
    }
}