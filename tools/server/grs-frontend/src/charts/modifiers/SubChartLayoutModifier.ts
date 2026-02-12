import { ChartModifierBase2D, EChart2DModifierType, Rect} from "scichart";


export class SubChartLayoutModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private xAxisLabel: string

    constructor(xAxisLabel = "") {
        super()
        this.xAxisLabel = xAxisLabel
    }

    onAttach(): void {
        this.updateLayout()

    }

    onAttachSubSurface(): void {
        this.updateLayout()
    }
    onDetachSubSurface(): void {
        this.updateLayout()
    }

    updateLayout() {
        const surface = this.parentSurface
        if (!surface) return

        const panes = surface.subCharts.filter(sc => sc.isVisible)
        const n = panes.length
        if (!n) return

        const extraSpace = n > 1 ? 0.075 : 0
        const baseHeight = (1.0 - extraSpace) / n
        const lastHeight = baseHeight + extraSpace

        let y = 0 
        panes.forEach((sc, i) => {
            const isBottom = i === n-1
            const h = isBottom ? lastHeight : baseHeight
            sc.subPosition = new Rect(0, y, 1, h)
            y += h

            // only show x axis of bottom panel
            const axis = sc.xAxes.get(0)

            axis.drawLabels = isBottom!
            axis.axisTitle = isBottom ? this.xAxisLabel : ""
            axis.isVisible = isBottom!

        })
    }
}