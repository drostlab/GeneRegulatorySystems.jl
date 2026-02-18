import { EXyDirection, MouseWheelZoomModifier, SciChartSurface, ZoomExtentsModifier, ZoomPanModifier, SeriesSelectionModifier, type TSciChart } from "scichart"
import { AxisSyncModifier } from "./modifiers/AxisSyncModifier"
import { DragGuardModifier } from "./modifiers/DragGuardModifier"
import { SelectSyncModifier, type GroupingFn } from "./modifiers/SelectSyncModifier"
import type { BasePanel, BasePanelOptions } from "./panels/BasePanel"
import type { TimeseriesPanel } from "./panels/TimeseriesPanel"
import type { Ref } from "vue"
import { appTheme } from "./theme"
import { TimelinePanel } from "./panels/TimelinePanel"
import { PromoterPanel } from "./panels/PromoterPanel"
import { CountsPanel } from "./panels/CountsPanel"
import { SubChartLayoutModifier } from "./modifiers/SubChartLayoutModifier"
import { SharedTimeCursorModifier } from "./modifiers/SharedTimeCursorModifier"
import { collectPathYRanges } from "./layout/rectangleLayout"
import { getPathTimeRanges } from "@/types/schedule"
import type { StructureNode, TimelineSegment, TimeseriesData, TimeseriesMetadata } from "@/types"
import { type SpeciesType } from "@/types/schedule"
import { useScheduleStore } from "@/stores/scheduleStore"

export type SelectionChangeCallback = (selectedGenes: string[]) => void
export type SegmentClickCallback = (segmentId: number, modelPath: string) => void
export type HoverChangeCallback = (modelPath: string | null) => void

export class MainChart {
    private surface!: SciChartSurface
    private wasmContext!: TSciChart
    private axisSynchroniser!: AxisSyncModifier
    private layoutModifier!: SubChartLayoutModifier
    private selectSyncModifier!: SelectSyncModifier
    private timeCursorModifier!: SharedTimeCursorModifier
    private tracks!: Array<{ id: string; panel: BasePanel }>
    private timepointChangeCallback?: (timepoint: number) => void
    private selectionChangeCallback?: SelectionChangeCallback
    private segmentClickCallback?: SegmentClickCallback
    private hoverChangeCallback?: HoverChangeCallback

    async init(containerRef: Ref<HTMLDivElement | undefined>) {
        const { sciChartSurface, wasmContext } = await SciChartSurface.create(containerRef.value!, { theme: appTheme })

        this.surface = sciChartSurface
        this.wasmContext = wasmContext

        await this.surface.registerFont("Montserrat", "/Montserrat-Regular.ttf")

        const options: BasePanelOptions = {
            parentSurface: this.surface,
            wasmContext: this.wasmContext,
            modifiers: [
                { modifierClass: DragGuardModifier },
                { modifierClass: ZoomPanModifier, args: { xyDirection: EXyDirection.XDirection } },
                { modifierClass: MouseWheelZoomModifier, args: { xyDirection: EXyDirection.XDirection } },
                { modifierClass: ZoomExtentsModifier },
                { modifierClass: SeriesSelectionModifier, args: { enableSelection: true, enableHover: true } }
            ]
        }

        this.tracks = [
            { id: 'schedule', panel: new TimelinePanel(options) },
            { id: 'active', panel: new PromoterPanel(options) },
            { id: 'elongations', panel: new CountsPanel(options, "Elongations") },
            { id: 'premrnas', panel: new CountsPanel(options, "Pre-mRNAs") },
            { id: 'mrnas', panel: new CountsPanel(options, "mRNAs") },
            { id: 'proteins', panel: new CountsPanel(options, "Proteins") }
        ]

        this.layoutModifier = new SubChartLayoutModifier("Time")
        this.surface.chartModifiers.add(this.layoutModifier)

        this.axisSynchroniser = new AxisSyncModifier()
        this.surface.chartModifiers.add(this.axisSynchroniser)
        this.timeCursorModifier = new SharedTimeCursorModifier(t => this.timepointChangeCallback?.(t))
        this.surface.chartModifiers.add(this.timeCursorModifier)

        /** Groups timeseries by gene ID (prefix before ':'); excludes segment rectangles. */
        const geneGroupFn: GroupingFn = (name) => {
            if (name.startsWith('segment:')) return null
            const colonIndex = name.indexOf(':')
            return colonIndex >= 0 ? name.substring(0, colonIndex) : name
        }

        this.selectSyncModifier = new SelectSyncModifier(geneGroupFn, genes => this.selectionChangeCallback?.(genes))
        this.surface.chartModifiers.add(this.selectSyncModifier)

        const timelinePanel = this.getTimelinePanel()
        timelinePanel.onSegmentClick((segmentId, modelPath) => {
            this.segmentClickCallback?.(segmentId, modelPath)
        })
        timelinePanel.onHoverChange((modelPath) => {
            this.hoverChangeCallback?.(modelPath)
        })

        console.debug(`[MainChart] Initialised with ${this.tracks.length} tracks`)
    }

    onTimepointChange(callback: (timepoint: number) => void): void {
        this.timepointChangeCallback = callback
    }

    onSelectionChange(callback: SelectionChangeCallback): void {
        this.selectionChangeCallback = callback
    }

    onSegmentClick(callback: SegmentClickCallback): void {
        this.segmentClickCallback = callback
    }

    onHoverChange(callback: HoverChangeCallback): void {
        this.hoverChangeCallback = callback
    }

    /** Deselect any selected segment in the timeline panel. */
    deselectSegment(): void {
        this.getTimelinePanel().deselectSegment()
    }

    private getTimelinePanel(): TimelinePanel {
        return this.tracks.find(({ id }) => id === 'schedule')!.panel as TimelinePanel
    }

    private getPromoterPanel(): PromoterPanel {
        return this.tracks.find(({ id }) => id === 'active')!.panel as PromoterPanel
    }

    private getTimeseriesPanels(): Array<{ id: string; panel: TimeseriesPanel }> {
        return this.tracks
            .filter(({ panel }) => panel instanceof (PromoterPanel as any) || panel instanceof (CountsPanel as any))
            .map(({ id, panel }) => ({ id, panel: panel as TimeseriesPanel }))
    }

    setVisibleTracks(ids: string[]) {
        this.tracks.forEach(({ id, panel }) => {
            panel.isVisible = ids.includes(id)
        })
        this.layoutModifier.updateLayout()
        this.timeCursorModifier?.onSubChartVisibilityChanged()
    }

    clear() {
        this.selectSyncModifier?.clearSelection()
        this.timeCursorModifier?.hideCursor()
        this.tracks.forEach(({ panel }) => {
            panel.clearData()
        })
    }

    dispose(): void {
        this.tracks?.forEach(({ panel }) => panel.dispose())
        this.surface?.delete()
    }

    setSimulationData(timeseries: TimeseriesData): void {
        const scheduleStore = useScheduleStore()
        const timeseriesPanels = this.getTimeseriesPanels()
        console.debug(`[MainChart] setSimulationData: ${Object.keys(timeseries).length} species, ${timeseriesPanels.length} panels`)

        timeseriesPanels.forEach(({ id, panel }) => {
            const speciesIds = new Set(scheduleStore.getSpeciesForSpeciesType(id as SpeciesType))
            const filteredTimeseries = Object.fromEntries(
                Object.entries(timeseries)
                    .filter(([species]) => speciesIds.has(species))
            ) as TimeseriesData
            panel.setData(filteredTimeseries)
            // Only zoom if the panel has data to avoid NaN range errors
            if (panel.surface.renderableSeries.asArray().length > 0) {
                panel.surface.zoomExtentsY()
            }
        })

        // Series were recreated -- re-apply selection state so SelectSync stays consistent
        this.selectSyncModifier?.reapplySelection()
    }

    setScheduleData(structure: StructureNode, segments: TimelineSegment[], metadata: TimeseriesMetadata): void {
        console.debug(`[MainChart] setScheduleData: ${segments.length} segments, structure type: ${structure.type}`)
        const timelinePanel = this.getTimelinePanel()
        timelinePanel.setScheduleData(structure, segments)

        const pathYRanges = collectPathYRanges(structure)
        const promoterPanel = this.getPromoterPanel()
        promoterPanel.setPathYRanges(pathYRanges)

        const pathTimeRanges = getPathTimeRanges(segments)
        const timeseriesPanels = this.getTimeseriesPanels()
        timeseriesPanels.forEach(({ panel }) => {
            panel.setMetadata(metadata)
            panel.setPathTimeRanges(pathTimeRanges)
        })
        this.tracks.forEach(({ panel }) => {
            panel.setTimeExtent(metadata.time_extent.min, metadata.time_extent.max)
        })
    }

    clearSimulationData(): void {
        this.selectSyncModifier?.clearSelection()
        this.timeCursorModifier?.hideCursor()
        this.getTimeseriesPanels().forEach(({ panel }) => panel.clearData())
    }

    /**
     * Append incremental streaming data to the appropriate timeseries panels.
     * Routes each species to its panel by species type.
     *
     * @param timeseries - Incremental timeseries from the current WS batch
     * @param currentTime - Current simulation time for x-axis range
     */
    appendStreamingData(timeseries: TimeseriesData, currentTime: number): void {
        const scheduleStore = useScheduleStore()
        const timeseriesPanels = this.getTimeseriesPanels()

        timeseriesPanels.forEach(({ id, panel }) => {
            const speciesIds = new Set(scheduleStore.getSpeciesForSpeciesType(id as SpeciesType))
            const filteredTimeseries = Object.fromEntries(
                Object.entries(timeseries)
                    .filter(([species]) => speciesIds.has(species))
            ) as TimeseriesData

            if (Object.keys(filteredTimeseries).length > 0) {
                panel.appendStreamingData(filteredTimeseries)
                // Only zoom if the panel has data to avoid NaN range errors
                if (panel.surface.renderableSeries.asArray().length > 0) {
                    panel.surface.zoomExtentsY()
                }
            }
        })

        // Update x-axis visible range to current time
        if (currentTime > 0) {
            this.tracks.forEach(({ panel }) => {
                panel.setVisibleTimeRange(0, currentTime)
            })
            // Move the time cursor line to current simulation time
            this.timeCursorModifier?.setCursorTime(currentTime)
        }
    }
}