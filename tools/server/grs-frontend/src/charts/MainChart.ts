import { EXyDirection, MouseWheelZoomModifier, SciChartSurface, ZoomExtentsModifier, ZoomPanModifier, type TSciChart } from "scichart";
import { AxisSyncModifier } from "./modifiers/AxisSyncModifier";
import type { BasePanel, BasePanelOptions } from "./panels/BasePanel";
import type { TimeseriesPanel } from "./panels/TimeseriesPanel";
import type { Ref } from "vue";
import { appTheme } from "./theme";
import { TimelinePanel } from "./panels/TimelinePanel";
import { PromoterPanel } from "./panels/PromoterPanel";
import { CountsPanel } from "./panels/CountsPanel";
import { SubChartLayoutModifier } from "./modifiers/SubChartLayoutModifier";
import { SharedTimeCursorModifier } from "./modifiers/SharedTimeCursorModifier";
import type { TimelineSegment, TimeseriesData, TimeseriesMetadata } from "@/types";
import { type SpeciesType } from "@/types/schedule";
import { useScheduleStore } from "@/stores/scheduleStore";




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

        const options: BasePanelOptions = {
            parentSurface: this.surface,
            wasmContext: this.wasmContext,
            modifiers: [
                { modifierClass: ZoomPanModifier, args: { xyDirection: EXyDirection.XDirection } },
                { modifierClass: MouseWheelZoomModifier, args: { xyDirection: EXyDirection.XDirection } },
                { modifierClass: ZoomExtentsModifier }
            ]
        }

        this.tracks = [
            {id: 'schedule', panel: new TimelinePanel(options)},
            {id: 'active', panel: new PromoterPanel(options)},
            {id: 'elongations', panel: new CountsPanel(options, "Elongations")},
            {id: 'premrnas', panel: new CountsPanel(options, "Pre-mRNAs")},
            {id: 'mrnas', panel: new CountsPanel(options, "mRNAs")},
            {id: 'proteins', panel: new CountsPanel(options, "Proteins")}
        ]

        this.layoutModifier = new SubChartLayoutModifier("Time")
        this.surface.chartModifiers.add(this.layoutModifier)

        this.axisSynchroniser = new AxisSyncModifier()
        this.surface.chartModifiers.add(this.axisSynchroniser)
        this.surface.chartModifiers.add(new SharedTimeCursorModifier(t => this.timepointChangeCallback?.(t)))
    }

    onTimepointChange(callback: (timepoint: number) => void): void {
        this.timepointChangeCallback = callback
    }

    private getTimeseriesPanels(): Array<{id: string; panel: TimeseriesPanel}> {
        return this.tracks
            .filter(({panel}) => panel instanceof (PromoterPanel as any) || panel instanceof (CountsPanel as any))
            .map(({id, panel}) => ({id, panel: panel as TimeseriesPanel}))
    }

    setVisibleTracks(ids: string[]) {
        this.tracks.forEach(({id, panel}) => {
            panel.isVisible = ids.includes(id)
        })
        this.layoutModifier.updateLayout()
    }

    clear() {

    }

    dispose() {

    }

    setSimulationData(timeseries: TimeseriesData): void {
        const scheduleStore = useScheduleStore()
        const timeseriesPanels = this.getTimeseriesPanels()
        
        timeseriesPanels.forEach(({id, panel}) => {
            const speciesIds = new Set(scheduleStore.getSpeciesForSpeciesType(id as SpeciesType))
            const filteredTimeseries = Object.fromEntries(
                Object.entries(timeseries)
                    .filter(([species]) => speciesIds.has(species))
            ) as TimeseriesData
            panel.setData(filteredTimeseries)
            panel.surface.zoomExtentsY()
        })
    }

    setScheduleData(segments: TimelineSegment[], metadata: TimeseriesMetadata): void {
        const timeseriesPanels = this.getTimeseriesPanels()
        timeseriesPanels.forEach(({panel}) => {
            panel.setMetadata(metadata)
        })
        this.tracks.forEach(({panel}) => {
            panel.setTimeExtent(metadata.time_extent.min, metadata.time_extent.max)
        })
    }

    clearSimulationData(): void {

    }
}