import { ChartModifierBase2D, EChart2DModifierType, ModifierMouseArgs, type IRenderableSeries } from "scichart"

/**
 * Modifier that synchronises selection state across all subcharts for series with matching names.
 * When a series is selected in one subchart, all series with the same dataSeriesName
 * across all subcharts will have their isSelected property set to true.
 */
export class SelectSyncModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private seriesByName: Map<string, Set<IRenderableSeries>> = new Map()
    private selectedSeriesNames: Set<string> = new Set()
    private onSelectionChange?: (selectedSeriesNames: string[]) => void

    /**
     * @param callback - Called when selection changes, receives array of selected series names
     */
    constructor(callback?: (selectedSeriesNames: string[]) => void) {
        super()
        this.onSelectionChange = callback
    }

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
     * Handles mouse click to detect selected series and synchronise selection state.
     * @param args - Mouse event arguments
     */
    modifierMouseUp(args: ModifierMouseArgs): void {
        super.modifierMouseUp(args)
        
        console.debug('modifierMouseUp triggered')
        
        const currentlySelected = new Set<string>()

        // find which series are currently selected
        this.parentSurface.subCharts.forEach(subChart => {
            subChart.renderableSeries.asArray().forEach(series => {
                if (series.isSelected) {
                    const name = series.dataSeries?.dataSeriesName
                    console.debug('Found selected series:', name)
                    if (name) currentlySelected.add(name)
                }
            })
        })

        console.debug('Currently selected series:', [...currentlySelected])

        // check if selection state changed
        const selectionChanged = 
            currentlySelected.size !== this.selectedSeriesNames.size ||
            [...currentlySelected].some(name => !this.selectedSeriesNames.has(name))

        if (selectionChanged) {
            this.syncSelectionState(currentlySelected)
            this.selectedSeriesNames = currentlySelected
            console.debug('Selection changed:', [...currentlySelected])
            this.onSelectionChange?.([...currentlySelected])
        }
    }

    /**
     * Synchronises the isSelected property across all series with matching names.
     * @param selectedNames - Set of series names that should be selected
     */
    private syncSelectionState(selectedNames: Set<string>): void {
        this.seriesByName.forEach((seriesSet, seriesName) => {
            const shouldBeSelected = selectedNames.has(seriesName)
            seriesSet.forEach(series => {
                series.isSelected = shouldBeSelected
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

    /**
     * Clears all selections across all series.
     */
    public clearSelection(): void {
        this.syncSelectionState(new Set())
        this.selectedSeriesNames.clear()
        this.onSelectionChange?.([])
    }
}
