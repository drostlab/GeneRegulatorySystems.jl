import { ChartModifierBase2D, EChart2DModifierType, Rect, SciChartSubSurface, SciChartVerticalGroup } from "scichart";

/** Minimum / maximum y-axis title font size (px). */
const MIN_TITLE_FONT = 7
const MAX_TITLE_FONT = 14
/** Fraction of panel pixel height used for axis title font scaling. */
const TITLE_FONT_SCALE = 0.046


export class SubChartLayoutModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private xAxisLabel: string
    private verticalGroup: SciChartVerticalGroup
    private groupedSurfaces = new Set<object>()
    private onResized = () => this.updateLayout()

    constructor(xAxisLabel = "") {
        super()
        this.xAxisLabel = xAxisLabel
        this.verticalGroup = new SciChartVerticalGroup()
    }

    onAttach(): void {
        this.parentSurface.resized.subscribe(this.onResized)
        this.updateLayout()
    }

    onDetach(): void {
        this.parentSurface?.resized.unsubscribe(this.onResized)
    }

    onAttachSubSurface(): void {
        this.updateLayout()
    }
    onDetachSubSurface(subSurface: SciChartSubSurface): void {
        if (this.groupedSurfaces.has(subSurface)) {
            this.verticalGroup.removeSurface(subSurface)
            this.groupedSurfaces.delete(subSurface)
        }
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
            if (!this.groupedSurfaces.has(sc)) {
                this.verticalGroup.addSurfaceToGroup(sc)
                this.groupedSurfaces.add(sc)
            }
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

        // Adapt y-axis title font size to absolute panel pixel height.
        // Use baseHeight for all panes to ensure consistent font sizes.
        // panelHeightPx already captures both viewport size and number of panels.
        const parentHeight = surface.renderSurface?.viewportSize?.height ?? 0
        if (parentHeight > 0) {
            const panelHeightPx = baseHeight * parentHeight
            const fontSize = Math.round(
                Math.max(MIN_TITLE_FONT, Math.min(MAX_TITLE_FONT, panelHeightPx * TITLE_FONT_SCALE))
            )
            panes.forEach((sc) => {
                for (const yAxis of sc.yAxes.asArray()) {
                    yAxis.axisTitleStyle = { ...yAxis.axisTitleStyle, fontSize }
                }
            })
        }
    }
}