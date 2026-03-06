import { ChartModifierBase2D, NumberRange, SciChartSubSurface, type SciChartSurface, type TSciChart } from "scichart";
import { getSciChartTheme } from "../theme";
import { getTheme, type ThemeMode } from "@/config/theme";

export const PATH_DIM_OPACITY = 0.2


export interface BasePanelOptions {
    parentSurface: SciChartSurface
    wasmContext: TSciChart
    isDark: boolean
    modifiers?: Array<{
        modifierClass: new (args?: any) => ChartModifierBase2D
        args?: any
    }>
}

export abstract class BasePanel {
    surface: SciChartSubSurface
    wasmContext: TSciChart
    parentSurface: SciChartSurface
    protected theme: ThemeMode

    constructor({parentSurface, wasmContext, isDark, modifiers = []}: BasePanelOptions) {
        this.parentSurface = parentSurface
        this.wasmContext = wasmContext
        this.theme = getTheme(isDark)
        this.surface = SciChartSubSurface.createSubSurface(parentSurface, {theme: getSciChartTheme(isDark)})

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

    /** Update visible range without changing the limit (for streaming). */
    setVisibleTimeRange(minTime: number, maxTime: number): void {
        const xAxis = this.surface.xAxes.get(0)
        if (xAxis) {
            xAxis.visibleRange = new NumberRange(minTime, maxTime)
        }
    }

    clearData(): void {
        this.surface.renderableSeries.asArray().forEach(rs => {
            rs.dataSeries?.delete()
        })
        this.surface.renderableSeries.clear()
        // Note: annotations are NOT cleared here -- modifiers manage their own annotations
    }

    /** Re-apply theme colours after a dark-mode toggle. */
    applyTheme(isDark: boolean): void {
        this.theme = getTheme(isDark)
        this.surface.applyTheme(getSciChartTheme(isDark))
        // Update explicitly-set grid line colours
        for (const axis of this.surface.yAxes.asArray()) {
            axis.majorGridLineStyle = { color: this.theme.chart.gridLine }
            axis.minorGridLineStyle = { color: this.theme.chart.gridLine }
        }
    }

    /**
     * Dim all series except those belonging to `path`. Pass null to restore all.
     * Series are identified by `<prefix>:<path>` in dataSeriesName.
     * Skips internal series (prefixed `__`) and segment rectangles.
     */
    highlightPath(path: string | null): void {
        for (const rs of this.surface.renderableSeries.asArray()) {
            const name = rs.dataSeries?.dataSeriesName ?? ''
            if (name.startsWith('__') || name.startsWith('segment:')) continue
            const colonIdx = name.indexOf(':')
            if (colonIdx < 0) continue
            const seriesPath = name.substring(colonIdx + 1)
            rs.opacity = (path === null || seriesPath === path) ? 1 : PATH_DIM_OPACITY
        }
    }

    dispose(): void {
        this.clearData()
        // Sub-surface deletion is handled by the parent SciChartSurface.delete() cascade;
        // calling delete() here as well causes a double-deletion warning from SciChart.
    }
}