import { ChartModifierBase2D, EChart2DModifierType, Rect} from "scichart";


export class SubChartLayoutModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private spacing: number

    constructor(spacing = 0.02) {
        super()
        this.spacing = spacing
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

    private updateLayout() {
        const surface = this.parentSurface
        if (!surface) return

        const panes = surface.subCharts.filter(sc => sc.isVisible)
        const n = panes.length
        if (!n) return

        const lastChart = panes[n-1]
        const xAxis = lastChart?.xAxes.get(0)
        const axisHeight = xAxis?.getAxisSize?.() ?? 0
        const extraFraction = axisHeight / this.parentSurface.renderSurface?.viewportSize.height

        const totalGap = this.spacing * (n-1)
        const usable = 1 - totalGap - extraFraction
        const baseHeight = usable / n
        const lastHeight = baseHeight + extraFraction

        let y = 0 
        panes.forEach((sc, i) => {
            const isBottom = i === n-1
            const h = isBottom ? lastHeight : baseHeight
            sc.subPosition = new Rect(0, y, 1, h)
            y += h + this.spacing

            // only show x axis of bottom panel
            const axis = sc.xAxes.get(0)

            axis.drawLabels = isBottom!
            axis.drawMajorTickLines = isBottom!

        })
    }
}