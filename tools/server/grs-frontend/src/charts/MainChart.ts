import { EXyDirection, MouseWheelZoomModifier, RolloverModifier, SciChartSurface, ZoomExtentsModifier, ZoomPanModifier, SeriesSelectionModifier, type TSciChart } from "scichart"
import { AxisSyncModifier } from "./modifiers/AxisSyncModifier"
import { SelectSyncModifier, type GroupingFn } from "./modifiers/SelectSyncModifier"
import { SeriesSyncCoordinator } from "./SeriesSyncCoordinator"
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
import type { StructureNode, TimelineSegment, TimeseriesData, TimeseriesMetadata } from "@/types"
import { type SpeciesType } from "@/types/schedule"
import { useScheduleStore } from "@/stores/scheduleStore"

export type SelectionChangeCallback = (selectedGenes: string[]) => void
export type SegmentClickCallback = (segmentId: number, modelPath: string) => void

export class MainChart {
    private surface!: SciChartSurface
    private wasmContext!: TSciChart
    private axisSynchroniser!: AxisSyncModifier
    private layoutModifier!: SubChartLayoutModifier
    private selectSyncModifier!: SelectSyncModifier
    private tracks!: Array<{ id: string; panel: BasePanel }>
    private timepointChangeCallback?: (timepoint: number) => void
    private selectionChangeCallback?: SelectionChangeCallback
    private segmentClickCallback?: SegmentClickCallback

    async init(containerRef: Ref<HTMLDivElement | undefined>) {
        const { sciChartSurface, wasmContext } = await SciChartSurface.create(containerRef.value!, { theme: appTheme })

        this.surface = sciChartSurface
        this.wasmContext = wasmContext

        /** Groups timeseries by gene ID (prefix before ':'); excludes segment rectangles. */
        const geneGroupFn: GroupingFn = (name) => {
            if (name.startsWith('segment:')) return null
            const colonIndex = name.indexOf(':')
            return colonIndex >= 0 ? name.substring(0, colonIndex) : name
        }

        const coordinator = new SeriesSyncCoordinator(this.surface, geneGroupFn)

        const options: BasePanelOptions = {
            parentSurface: this.surface,
            wasmContext: this.wasmContext,
            coordinator,
            modifiers: [
                { modifierClass: ZoomPanModifier, args: { xyDirection: EXyDirection.XDirection } },
                { modifierClass: MouseWheelZoomModifier, args: { xyDirection: EXyDirection.XDirection } },
                { modifierClass: ZoomExtentsModifier },
                { modifierClass: SeriesSelectionModifier, args: { enableSelection: true, enableHover: true } },
                { modifierClass: RolloverModifier, args: {
                    showTooltip: true,
                    showRolloverLine: false,
                    showAxisLabel: false,
                    tooltipDataTemplate: seriesTooltipTemplate
                } }
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
        this.surface.chartModifiers.add(new SharedTimeCursorModifier(t => this.timepointChangeCallback?.(t)))

        this.selectSyncModifier = new SelectSyncModifier(geneGroupFn, genes => this.selectionChangeCallback?.(genes))
        this.surface.chartModifiers.add(this.selectSyncModifier)

        const timelinePanel = this.getTimelinePanel()
        timelinePanel.onSegmentClick((segmentId, modelPath) => {
            this.segmentClickCallback?.(segmentId, modelPath)
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
        console.debug(`[MainChart] setVisibleTracks: [${ids}]`)
        this.tracks.forEach(({ id, panel }) => {
            panel.isVisible = ids.includes(id)
        })
        this.layoutModifier.updateLayout()
    }

    clear() {
        this.selectSyncModifier?.clearSelection()
        this.tracks.forEach(({ panel }) => {
            panel.clearData()
        })
    }

    dispose() {
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
            panel.surface.zoomExtentsY()
        })
    }

    setScheduleData(structure: StructureNode, segments: TimelineSegment[], metadata: TimeseriesMetadata): void {
        console.debug(`[MainChart] setScheduleData: ${segments.length} segments, structure type: ${structure.type}`)
        const timelinePanel = this.getTimelinePanel()
        timelinePanel.setScheduleData(structure, segments)

        const pathYRanges = collectPathYRanges(structure)
        const promoterPanel = this.getPromoterPanel()
        promoterPanel.setPathYRanges(pathYRanges)

        const timeseriesPanels = this.getTimeseriesPanels()
        timeseriesPanels.forEach(({ panel }) => {
            panel.setMetadata(metadata)
        })
        this.tracks.forEach(({ panel }) => {
            panel.setTimeExtent(metadata.time_extent.min, metadata.time_extent.max)
        })
    }

    clearSimulationData(): void {
        this.selectSyncModifier?.clearSelection()
    }
}

/** Tooltip template for RolloverModifier: parses dataSeriesName conventions. */
function seriesTooltipTemplate(seriesInfo: any): string[] {
    const name: string = seriesInfo.seriesName ?? ''

    // Segment rectangle: "segment:123"
    if (name.startsWith('segment:')) {
        return [`Segment ${name.substring(8)}`]
    }

    // Timeseries: "geneId:executionPath"
    const colonIdx = name.indexOf(':')
    if (colonIdx >= 0) {
        const gene = name.substring(0, colonIdx)
        const path = name.substring(colonIdx + 1)
        const yVal = seriesInfo.yValue !== undefined ? Number(seriesInfo.yValue).toFixed(1) : ''
        return [`Gene: ${gene}`, `Path: ${path}`, yVal ? `Value: ${yVal}` : ''].filter(Boolean)
    }

    return [name]
}