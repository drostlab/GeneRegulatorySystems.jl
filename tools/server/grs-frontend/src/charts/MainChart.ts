import { MouseWheelZoomModifier, SciChartSurface, ZoomExtentsModifier, ZoomPanModifier, type TSciChart } from "scichart";
import { AxisSyncModifier } from "./modifiers/AxisSyncModifier";
import type { BasePanel, BasePanelOptions } from "./panels/BasePanel";
import type { Ref } from "vue";
import { appTheme } from "./theme";
import { TimelinePanel } from "./panels/TimelinePanel";
import { PromoterPanel } from "./panels/PromoterPanel";
import { CountsPanel } from "./panels/CountsPanel";
import { SubChartLayoutModifier } from "./modifiers/SubChartLayoutModifier";
import { SharedTimeCursorModifier } from "./modifiers/SharedTimeCursorModifier";
import type { TimelineSegment, TimeseriesData } from "@/types";




export class MainChart {
    private surface!: SciChartSurface
    private wasmContext!: TSciChart
    private axisSynchroniser!: AxisSyncModifier
    private layoutModifier!: SubChartLayoutModifier
    private tracks!: Array<{id: string; panel: BasePanel}>
    private timepointChangeCallback?: (timepoint: number) => void

    async init(containerRef: Ref<HTMLDivElement | undefined>) {
        const {sciChartSurface, wasmContext} = await SciChartSurface.create(containerRef.value!, {theme: appTheme})
        
        this.surface = sciChartSurface
        this.wasmContext = wasmContext

        const modifierClasses = [ZoomPanModifier, MouseWheelZoomModifier, ZoomExtentsModifier]

        const options: BasePanelOptions = {
            parentSurface: this.surface,
            wasmContext: this.wasmContext,
            modifierClasses: modifierClasses
        }

        this.tracks = [
            {id: 'schedule', panel: new TimelinePanel(options)},
            {id: 'active', panel: new PromoterPanel(options)},
            {id: 'elongations', panel: new CountsPanel(options, "Elongations")},
            {id: 'premrnas', panel: new CountsPanel(options, "Pre-mRNAs")},
            {id: 'rnas', panel: new CountsPanel(options, "mRNAs")},
            {id: 'proteins', panel: new CountsPanel(options, "Proteins")}
        ]

        this.layoutModifier = new SubChartLayoutModifier()
        this.surface.chartModifiers.add(this.layoutModifier)

        this.axisSynchroniser = new AxisSyncModifier()
        this.surface.chartModifiers.add(this.axisSynchroniser)
        this.surface.chartModifiers.add(new SharedTimeCursorModifier(t => this.timepointChangeCallback?.(t)))
    }

    onTimepointChange(callback: (timepoint: number) => void): void {
        this.timepointChangeCallback = callback
    }

    setVisibleTracks(ids: string[]) {
        this.tracks.forEach(({id, panel}) => {
            panel.isVisible = ids.includes(id)
        })
        this.layoutModifier.updateLayout()
    }

    setVisibleGenes(genes: string[]) {

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