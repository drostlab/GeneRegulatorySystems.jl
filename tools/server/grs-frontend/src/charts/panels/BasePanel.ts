import { ChartModifierBase2D, SciChartSubSurface, type SciChartSurface, type TSciChart } from "scichart";
import { appTheme } from "../theme";


export interface BasePanelOptions {
    parentSurface: SciChartSurface
    wasmContext: TSciChart
    modifierClasses?: Array<new () => ChartModifierBase2D>
}

export abstract class BasePanel {
    surface: SciChartSubSurface
    wasmContext!: TSciChart
    parentSurface: SciChartSurface

    constructor({parentSurface, wasmContext, modifierClasses = []}: BasePanelOptions) {
        this.parentSurface = parentSurface
        this.wasmContext = wasmContext
        this.surface = SciChartSubSurface.createSubSurface(parentSurface, {theme: appTheme})

        modifierClasses.forEach(ModifierClass => {
            this.surface.chartModifiers.add(new ModifierClass())
        })
    }

    get isVisible() {
        return this.surface.isVisible
    }

    set isVisible(value: boolean) {
        this.surface.isVisible = value
    }
}