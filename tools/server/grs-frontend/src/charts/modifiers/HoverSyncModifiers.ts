import { ChartModifierBase2D, EChart2DModifierType, ModifierMouseArgs, type IRenderableSeries } from "scichart"

/**
 * Modifier that synchronises hover state across all subcharts for series with matching names.
 * When a series is hovered in one subchart, all series with the same dataSeriesName
 * across all subcharts will have their isHovered property set to true.
 */
export class HoverSyncModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private seriesByName: Map<string, Set<IRenderableSeries>> = new Map()
    private hoveredSeriesName: string | null = null

    onAttach(): void {
        if (!this.parentSurface) return
        this.rebuildSeriesCache()
    }

    /**
     * Rebuilds the cache of series grouped by dataSeriesName.
     * Called when modifier is attached and should be called when series are added/removed.
     */
    private rebuildSeriesCache(): void {
        this.seriesByName.clear()
        
        this.parentSurface.subCharts.forEach(subChart => {
            subChart.renderableSeries.asArray().forEach(series => {
                const name = series.dataSeries?.dataSeriesName
                if (!name) return

                if (!this.seriesByName.has(name)) {
                    this.seriesByName.set(name, new Set())
                }
                this.seriesByName.get(name)!.add(series)
            })
        })
    }

    /**
     * Handles mouse movement to detect hovered series and synchronise hover state.
     * @param args - Mouse event arguments
     */
    modifierMouseMove(args: ModifierMouseArgs): void {
        super.modifierMouseMove(args)
        
        let currentlyHoveredName: string | null = null

        // find which series is currently hovered
        for (const subChart of this.parentSurface.subCharts) {
            for (const series of subChart.renderableSeries.asArray()) {
                if (series.isHovered) {
                    currentlyHoveredName = series.dataSeries?.dataSeriesName ?? null
                    break
                }
            }
            if (currentlyHoveredName) break
        }

        // if hover state changed, synchronise across all matching series
        if (currentlyHoveredName !== this.hoveredSeriesName) {
            this.syncHoverState(currentlyHoveredName)
            this.hoveredSeriesName = currentlyHoveredName
        }
    }

    /**
     * Handles mouse leave event to clear hover state.
     * @param args - Mouse event arguments
     */
    modifierMouseLeave(args: ModifierMouseArgs): void {
        super.modifierMouseLeave(args)
        this.syncHoverState(null)
        this.hoveredSeriesName = null
    }

    /**
     * Synchronises the isHovered property across all series with matching names.
     * @param hoveredName - Name of the currently hovered series, or null to clear all
     */
    private syncHoverState(hoveredName: string | null): void {
        this.seriesByName.forEach((seriesSet, seriesName) => {
            const shouldBeHovered = hoveredName !== null && seriesName === hoveredName
            seriesSet.forEach(series => {
                series.isHovered = shouldBeHovered
            })
        })
    }

    /**
     * Public method to manually rebuild the series cache.
     * Call this when series are dynamically added or removed.
     */
    public updateSeriesCache(): void {
        this.rebuildSeriesCache()
    }
}
