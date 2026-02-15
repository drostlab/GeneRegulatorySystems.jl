import { ChartModifierBase2D, EChart2DModifierType, ModifierMouseArgs, type IRenderableSeries } from "scichart"

/** Function that maps a dataSeriesName to a group key, or null to exclude. */
export type GroupingFn = (dataSeriesName: string) => string | null

export class SelectSyncModifier extends ChartModifierBase2D {
    public type = EChart2DModifierType.Custom
    private selectedGroups: Set<string> = new Set()
    private onSelectionChange?: (selectedGroups: string[]) => void
    private groupFn: GroupingFn

    constructor(groupFn: GroupingFn, callback?: (selectedGroups: string[]) => void) {
        super()
        this.groupFn = groupFn
        this.onSelectionChange = callback
    }

    modifierMouseUp(args: ModifierMouseArgs): void {
        super.modifierMouseUp(args)

        const currentlySelected = new Set<string>()

        for (const subChart of this.parentSurface.subCharts) {
            for (const series of subChart.renderableSeries.asArray()) {
                if (series.isSelected) {
                    const group = this.resolveGroup(series)
                    if (group) currentlySelected.add(group)
                }
            }
        }

        const selectionChanged =
            currentlySelected.size !== this.selectedGroups.size ||
            [...currentlySelected].some(g => !this.selectedGroups.has(g))

        if (selectionChanged) {
            this.syncSelectionState(currentlySelected)
            this.selectedGroups = currentlySelected
            console.debug(`[SelectSync] Selection changed: [${[...currentlySelected]}]`)
            this.onSelectionChange?.([...currentlySelected])
        }
    }

    private syncSelectionState(selectedGroups: Set<string>): void {
        for (const subChart of this.parentSurface.subCharts) {
            for (const series of subChart.renderableSeries.asArray()) {
                const group = this.resolveGroup(series)
                if (!group) continue
                series.isSelected = selectedGroups.has(group)
            }
        }
    }

    public clearSelection(): void {
        this.syncSelectionState(new Set())
        this.selectedGroups.clear()
        this.onSelectionChange?.([])
    }

    private resolveGroup(series: IRenderableSeries): string | null {
        const name = series.dataSeries?.dataSeriesName
        return name ? this.groupFn(name) : null
    }
}
