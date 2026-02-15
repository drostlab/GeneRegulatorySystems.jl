/**
 * Synchronises hover state across all subcharts by group key.
 *
 * Panels wire their series' `onHoveredChanged` callback into
 * `syncHover()`. A reentrancy guard prevents infinite recursion
 * when setting `isHovered` triggers sibling callbacks.
 *
 * Hover visual: non-hovered series are dimmed to DIMMED_OPACITY.
 * Series with null group (e.g. segment rectangles) are left untouched.
 */

import type { SciChartSurface, IRenderableSeries } from "scichart"
import type { GroupingFn } from "./modifiers/SelectSyncModifier"

const DIMMED_OPACITY = 0.3

export class SeriesSyncCoordinator {
    private isSyncing = false
    private parentSurface: SciChartSurface
    private groupFn: GroupingFn

    constructor(parentSurface: SciChartSurface, groupFn: GroupingFn) {
        this.parentSurface = parentSurface
        this.groupFn = groupFn
    }

    /** Call from each series' `onHoveredChanged`. Syncs hover + dims non-matching series. */
    syncHover(sourceSeries: IRenderableSeries): void {
        if (this.isSyncing) return
        this.isSyncing = true

        const group = this.resolveGroup(sourceSeries)
        const isHovered = sourceSeries.isHovered

        if (group && isHovered) {
            for (const subChart of this.parentSurface.subCharts) {
                for (const series of subChart.renderableSeries.asArray()) {
                    const seriesGroup = this.resolveGroup(series)
                    if (seriesGroup === null) continue  // skip ungrouped (segments)
                    if (seriesGroup === group) {
                        series.isHovered = true
                        series.opacity = 1
                    } else {
                        series.opacity = DIMMED_OPACITY
                    }
                }
            }
        } else {
            // Restore all grouped series to full opacity
            for (const subChart of this.parentSurface.subCharts) {
                for (const series of subChart.renderableSeries.asArray()) {
                    if (this.resolveGroup(series) === null) continue
                    series.isHovered = false
                    series.opacity = 1
                }
            }
        }

        // Force re-render on all subcharts
        this.parentSurface.invalidateElement()

        this.isSyncing = false
    }

    private resolveGroup(series: IRenderableSeries): string | null {
        const name = series.dataSeries?.dataSeriesName
        return name ? this.groupFn(name) : null
    }
}
