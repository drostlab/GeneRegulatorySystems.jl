import { NumericAxis, SciChartSubSurface, XyDataSeries } from "scichart"


export class CountTrackPanel extends SimulationTrackPanel {
    private yAxis!: NumericAxis

    async init(parentSurface, wasmContext): Promise<void> {
        this.surface = await SciChartSubSurface.create(parentSurface, {
            theme: parentSurface.theme,
        })

        const xyDataSeries = new XyDataSeries(wasmContext, {
            isSorted: true,
            containsNaN: false,

        })

    }

    updateData(data: TrackSeriesData[])
}