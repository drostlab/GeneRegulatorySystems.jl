import { ChartModifierBase2D, NumberRange, SciChartSubSurface, type SciChartSurface, type TSciChart } from "scichart";
import { appTheme } from "../theme";
import type { SeriesSyncCoordinator } from "../SeriesSyncCoordinator";


export interface BasePanelOptions {
    parentSurface: SciChartSurface
    wasmContext: TSciChart
    coordinator: SeriesSyncCoordinator
    modifiers?: Array<{
        modifierClass: new (args?: any) => ChartModifierBase2D
        args?: any
    }>
}

export abstract class BasePanel {
    surface: SciChartSubSurface
    wasmContext: TSciChart
    parentSurface: SciChartSurface
    protected coordinator: SeriesSyncCoordinator

    constructor({parentSurface, wasmContext, coordinator, modifiers = []}: BasePanelOptions) {
        this.parentSurface = parentSurface
        this.wasmContext = wasmContext
        this.coordinator = coordinator
        this.surface = SciChartSubSurface.createSubSurface(parentSurface, {theme: appTheme})

        modifiers.forEach(({modifierClass: ModifierClass, args}) => {
            this.surface.chartModifiers.add(new ModifierClass(args))
        })
    }

    get isVisible() {
        return this.surface.isVisible
    }

    set isVisible(value: boolean) {
        this.surface.isVisible = value
    }

    setTimeExtent(minTime: number, maxTime: number): void {
        const xAxis = this.surface.xAxes.get(0)
        if (xAxis) {
            xAxis.visibleRange = new NumberRange(minTime, maxTime)
            xAxis.visibleRangeLimit = new NumberRange(minTime, maxTime)
        }
    }
}