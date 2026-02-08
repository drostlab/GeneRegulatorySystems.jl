import {
    NumericAxis,
    SciChartSurface,
    type TSciChart,
    Rect,
    SciChartSubSurface,
    sciChartConfig,
    ZoomPanModifier,
    MouseWheelZoomModifier,
    ZoomExtentsModifier,
    EWatermarkPosition,
    NumberRange,
    EventHandler,
    EAxisAlignment,
    RolloverModifier
} from 'scichart'
import type { Ref } from 'vue'
import { appTheme } from './theme'
import { type TimeseriesData, type TimelineSegment, SPECIES_TYPES } from '@/types'
import { speciesTypeLabels } from '@/types/schedule'

const allTracks: Array<{ label: string; value: string }> = [
    { label: 'Schedule Timeline', value: 'schedule' },
].concat(
    SPECIES_TYPES.map(type => ({
        label: speciesTypeLabels[type],
        value: type
    }))
)

export class ChartManager {
    private surface!: SciChartSurface
    private wasmContext!: TSciChart
    private axisSynchroniser!: AxisSynchroniser
    private xAxisLabel = "Time"
    private tracks: Array<{ label: string; value: string; isVisible: boolean }> = []
    private timepointChangeCallback?: (timepoint: number) => void

    async init(containerRef: Ref<HTMLDivElement | undefined>) {
        const {sciChartSurface, wasmContext} = await SciChartSurface.create(containerRef.value!, {theme: appTheme})

        this.surface = sciChartSurface
        this.wasmContext = wasmContext
        this.axisSynchroniser = new AxisSynchroniser()

        // Create all tracks on mount, we just need to set which ones are visible really.
        this.tracks = allTracks.map(track => ({...track, isVisible: true}))
        this.tracks.forEach(track => this.addTrackPanel(track.label))

        this.updateSubChartPositions()
        this.updateXAxisVisibility()

        
    }



    /**
     * Register callback to be called when timepoint changes (e.g., from scrubbing)
     */
    onTimepointChange(callback: (timepoint: number) => void): void {
        this.timepointChangeCallback = callback
    }

    setVisibleTracks(tracks: string[]) {
        this.tracks.forEach(track => {
            track.isVisible = tracks.includes(track.value)
        })
        this.updateSubChartPositions()
        this.updateXAxisVisibility()
    }

    setVisibleGenes(genes: string[]) {

    }

    private addTrackPanel(label: string): void {
        const newChart = SciChartSubSurface.createSubSurface(this.surface, {
            theme: appTheme
        })

        const xAxis = new NumericAxis(this.wasmContext, {
            axisTitle: this.xAxisLabel,
            labelStyle: {fontSize: 10},
            axisTitleStyle: {fontSize: 12, fontFamily: "Montserrat"}
        })
        const yAxis = new NumericAxis(this.wasmContext, {
            axisTitle: label,
            axisAlignment: EAxisAlignment.Left,
            labelStyle: {fontSize: 10},
            axisTitleStyle: {fontSize: 12, fontFamily: "Montserrat"}
        })
        newChart.xAxes.add(xAxis)
        newChart.yAxes.add(yAxis)

        newChart.chartModifiers.add(new ZoomPanModifier())
        newChart.chartModifiers.add(new MouseWheelZoomModifier())
        newChart.chartModifiers.add(new ZoomExtentsModifier())
        const rollover = new RolloverModifier({showAxisLabel: true, showTooltip: true})

        newChart.chartModifiers.add(rollover)

        this.axisSynchroniser.addAxis(xAxis)
        this.updateXAxisVisibility()
    }

    private updateSubChartPositions() {
        const visibleCharts = this.tracks.map((t, i) => ({ track: t, index: i })).filter(c => c.track.isVisible)
        const numVisible = visibleCharts.length
        const charts = this.surface.subCharts

        // Allocate ~5% extra space to the last visible chart to account for x-axis
        const extraSpace = numVisible > 1 ? 0.075    : 0
        const baseHeight = (1.0 - extraSpace) / numVisible
        const lastHeight = baseHeight + extraSpace

        let position = 0
        this.tracks.forEach((track, i) => {
            const chart = charts[i]
            chart!.isVisible = track.isVisible

            if (track.isVisible) {
                const isLastVisible = visibleCharts[numVisible - 1]?.index === i
                const height = isLastVisible ? lastHeight : baseHeight
                chart!.subPosition = new Rect(0, position, 1, height)
                position += height
            }
        })
    }

    private updateXAxisVisibility() {
        const charts = this.surface.subCharts
        const lastVisibleIndex = this.tracks.findIndex((t, i) => t.isVisible && !this.tracks.slice(i + 1).some(tr => tr.isVisible))

        charts.forEach((chart, i) => {
            const axis = chart.xAxes.get(0)
            const isBottom = i === lastVisibleIndex && this.tracks[i]?.isVisible

            axis.drawLabels = isBottom!
            axis.drawMajorTickLines = isBottom!
            axis.axisTitle = isBottom ? this.xAxisLabel : ""
        })
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
    visibleRange: NumberRange = new NumberRange(0,10);
    axes: NumericAxis[] = [];

    visibleRangeChanged: EventHandler<any>

    constructor(initialRange?: NumberRange, axes?:NumericAxis[]) {
        this.visibleRange = initialRange ?? this.visibleRange
        this.visibleRangeChanged = new EventHandler()

        this.publishChange = this.publishChange.bind(this)
        if (axes) {
            axes.forEach(a => this.addAxis(a))
        }
    }

    publishChange(data) {
        this.visibleRange = data.visibleRange
        this.axes.forEach(a => (a.visibleRange = this.visibleRange))
        this.visibleRangeChanged.raiseEvent(data)
    }

    addAxis(axis) {
        if (!this.axes.includes(axis)) {
            this.axes.push(axis)
            axis.visibleRange = this.visibleRange
            axis.visibleRangeChanged.subscribe(this.publishChange)
        }
    }

    removeAxis(axis) {
        const index = this.axes.findIndex(a => a == axis)
        if (index >= 0) {
            this.axes.splice(index, 1)
            axis.visibleRange.unsubscribe(this.publishChange)
        }
    }



}
