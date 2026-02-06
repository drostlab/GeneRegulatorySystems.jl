import {
    NumericAxis,
    SciChartSurface,
    type TSciChart
} from 'scichart'
import type { Ref } from 'vue'
import { appTheme } from './theme'
import type { TimeseriesData, TimelineSegment } from '@/types'


export class ChartManager {
    private surface!: SciChartSurface
    private wasmContext!: TSciChart
    private axisSynchroniser!: AxisSynchroniser
    private timepointChangeCallback?: (timepoint: number) => void

    async init(containerRef: Ref<HTMLDivElement | undefined>) {
        const {sciChartSurface, wasmContext} = await SciChartSurface.create(containerRef.value!, {theme: appTheme})

        this.surface = sciChartSurface
        this.wasmContext = wasmContext
        this.axisSynchroniser = new AxisSynchroniser()

        
    }

    /**
     * Register callback to be called when timepoint changes (e.g., from scrubbing)
     */
    onTimepointChange(callback: (timepoint: number) => void): void {
        this.timepointChangeCallback = callback
    }

    setVisibleTracks(tracks: string[]) {

    }

    setVisibleGenes(genes: string[]) {

    }

    addTrackPanel() {

    }

    removeTrackPanel() {

    }

    clear() {

    }

    dispose() {

    }

    setSimulationData(timeseries: TimeseriesData): void {

    }

    setScheduleData(segments: TimelineSegment[]): void {

    }

    clearSimulationData(): void {

}
    


}

class AxisSynchroniser {


}
