import { EAxisAlignment, FastBandRenderableSeries, NumericAxis, SweepAnimation, XyyDataSeries } from "scichart"
import { TimeseriesPanel } from "./TimeseriesPanel"
import type { BasePanelOptions } from "./BasePanel"
import type { TimeseriesData } from "@/types/simulation"
import { restructureTimeseriesByPathAndGene } from "@/types/simulation"
import { getGeneFromSpeciesName } from "@/types/schedule"
import { CHART_FONT_FAMILY, CHART_FONT_SIZES, AXIS_THICKNESS } from "../chartConstants"

const SWEEP_DURATION_MS = 400

export type PathYRanges = Map<string, { yMin: number; yMax: number }>

export class PromoterPanel extends TimeseriesPanel {
    private pathYRanges: PathYRanges = new Map()

    /** Persistent data series map for streaming: `geneId:path` -> XyyDataSeries */
    private seriesMap: Map<string, XyyDataSeries> = new Map()

    /** Series keys that currently have a trailing cursor extension point */
    private cursorKeys: Set<string> = new Set()

    /** Cached band layout params per series key: { yCenter, bandHeight } */
    private bandParams: Map<string, { yCenter: number; bandHeight: number }> = new Map()

    constructor(options: BasePanelOptions) {
        super(options)

        const xAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Time",
            labelStyle: { fontSize: CHART_FONT_SIZES.label },
            axisTitleStyle: { fontSize: CHART_FONT_SIZES.title, fontFamily: CHART_FONT_FAMILY },
            drawMajorBands: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false
        })

        const yAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Promoter Activity",
            axisAlignment: EAxisAlignment.Left,
            axisTitleStyle: { fontSize: CHART_FONT_SIZES.title, fontFamily: CHART_FONT_FAMILY },
            drawMajorBands: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false,
            drawMajorTickLines: false,
            drawMinorTickLines: false,
            drawLabels: false,
            axisThickness: AXIS_THICKNESS
        })

        this.surface.xAxes.add(xAxis)
        this.surface.yAxes.add(yAxis)
    }

    setPathYRanges(ranges: PathYRanges): void {
        this.pathYRanges = ranges
        this._precomputeBandParams()
    }

    override setMetadata(metadata: TimeseriesMetadata | null): void {
        super.setMetadata(metadata)
        this._precomputeBandParams()
    }

    /**
     * Pre-compute yCenter and bandHeight for every (gene, path) combination
     * so streaming can use correct layout without needing all data up front.
     */
    private _precomputeBandParams(): void {
        this.bandParams.clear()
        if (!this.metadata || this.pathYRanges.size === 0) return

        const sortedGenes = [...this.metadata.genes].sort()
        const genesCount = sortedGenes.length
        if (genesCount === 0) return

        for (const [path, yRange] of this.pathYRanges) {
            const bandHeight = (yRange.yMax - yRange.yMin) / genesCount
            sortedGenes.forEach((geneId, geneIndex) => {
                const key = `${geneId}:${path}`
                const yCenter = yRange.yMin + geneIndex * bandHeight + 0.5 * bandHeight
                this.bandParams.set(key, { yCenter, bandHeight })
            })
        }
    }

    override clearData(): void {
        this.seriesMap.clear()
        this.cursorKeys.clear()
        // Note: bandParams is NOT cleared here -- it's layout, recomputed from setMetadata/setPathYRanges
        super.clearData()
    }

    setData(timeseries: TimeseriesData): void {
        this.clearData()
        if (!timeseries || !this.metadata) return

        const dataByPath = restructureTimeseriesByPathAndGene(timeseries, this.metadata)
        console.debug(`[PromoterPanel] setData: ${Object.keys(dataByPath).length} paths in data, ${this.pathYRanges.size} paths in yRanges`)

        for (const [path, geneData] of Object.entries(dataByPath)) {
            const yRange = this.pathYRanges.get(path)
            if (!yRange) continue

            const sortedGenes = Object.keys(geneData).sort()
            const genesCount = sortedGenes.length
            const bandHeight = (yRange.yMax - yRange.yMin) / genesCount

            sortedGenes.forEach((geneId, geneIndex) => {
                const { colour, series } = geneData[geneId]!
                const yCenter = yRange.yMin + geneIndex * bandHeight + 0.5 * bandHeight
                const key = `${geneId}:${path}`

                // Cache band layout for streaming
                this.bandParams.set(key, { yCenter, bandHeight })

                const { xData, yTop, yBottom } = this._buildBandArrays(series, yCenter, bandHeight)

                const xyyDataSeries = new XyyDataSeries(this.wasmContext, {
                    isSorted: true,
                    containsNaN: false,
                    dataSeriesName: key
                })
                if (xData.length > 0) {
                    xyyDataSeries.appendRange(xData, yTop, yBottom)
                }
                this.seriesMap.set(key, xyyDataSeries)

                const coordinator = this.coordinator
                const bandSeries = new FastBandRenderableSeries(this.wasmContext, {
                    dataSeries: xyyDataSeries,
                    stroke: colour,
                    strokeThickness: 0.0,
                    fillY1: colour,
                    strokeY1: colour,
                    animation: new SweepAnimation({ duration: SWEEP_DURATION_MS }),
                    onHoveredChanged: (sourceSeries) => {
                        coordinator.syncHover(sourceSeries)
                    }
                })
                this.surface.renderableSeries.add(bandSeries)
            })
        }
    }

    appendStreamingData(timeseries: TimeseriesData, currentTime: number): void {
        if (!this.metadata) return

        for (const [species, pathData] of Object.entries(timeseries)) {
            for (const [path, points] of Object.entries(pathData)) {
                const geneId = getGeneFromSpeciesName(species) ?? ""
                const key = `${geneId}:${path}`

                const params = this.bandParams.get(key)
                if (!params) continue  // Skip if no pre-computed layout for this key

                let xyyData = this.seriesMap.get(key)
                if (!xyyData) {
                    xyyData = this._createStreamingSeries(key, geneId)
                }

                // Remove trailing cursor point
                this._removeCursorPoint(key, xyyData)

                // Build and append band arrays from raw points
                const { yCenter, bandHeight } = params
                const { xData, yTop, yBottom } = this._buildBandArrays(points, yCenter, bandHeight)
                if (xData.length > 0) {
                    xyyData.appendRange(xData, yTop, yBottom)
                }

                // Add cursor point
                this._addCursorPoint(key, xyyData, currentTime)
            }
        }
    }

    /**
     * Convert raw timeseries points into digital band arrays.
     * For each transition, we duplicate the point at the new time with the old state
     * (creating a step), then add the point with the new state.
     */
    private _buildBandArrays(
        series: Array<[number, number]>,
        yCenter: number,
        bandHeight: number
    ): { xData: number[]; yTop: number[]; yBottom: number[] } {
        const xData: number[] = []
        const yTop: number[] = []
        const yBottom: number[] = []

        for (let i = 0; i < series.length; i++) {
            const [time, state] = series[i]!

            if (i > 0) {
                const prevState = series[i - 1]![1]
                const halfHeight = 0.5 * bandHeight * prevState
                xData.push(time)
                yTop.push(yCenter + halfHeight)
                yBottom.push(yCenter - halfHeight)
            }

            const halfHeight = 0.5 * bandHeight * state
            xData.push(time)
            yTop.push(yCenter + halfHeight)
            yBottom.push(yCenter - halfHeight)
        }

        return { xData, yTop, yBottom }
    }

    /** Create a new XyyDataSeries + FastBandRenderableSeries for streaming. */
    private _createStreamingSeries(key: string, geneId: string): XyyDataSeries {
        const colour = this.metadata!.gene_colours[geneId] ?? "gray"
        const xyyData = new XyyDataSeries(this.wasmContext, {
            isSorted: true,
            containsNaN: false,
            dataSeriesName: key
        })
        this.seriesMap.set(key, xyyData)

        const coordinator = this.coordinator
        const bandSeries = new FastBandRenderableSeries(this.wasmContext, {
            dataSeries: xyyData,
            stroke: colour,
            strokeThickness: 0.0,
            fillY1: colour,
            strokeY1: colour,
            onHoveredChanged: (sourceSeries) => {
                coordinator.syncHover(sourceSeries)
            }
        })
        this.surface.renderableSeries.add(bandSeries)
        return xyyData
    }

    /** Remove trailing cursor extension point if present. */
    private _removeCursorPoint(key: string, xyyData: XyyDataSeries): void {
        if (!this.cursorKeys.has(key)) return
        const count = xyyData.count()
        if (count > 0) {
            xyyData.removeRange(count - 1, 1)
        }
        this.cursorKeys.delete(key)
    }

    /** Add trailing cursor point extending the last state to currentTime (clamped to path end). */
    private _addCursorPoint(key: string, xyyData: XyyDataSeries, currentTime: number): void {
        const count = xyyData.count()
        if (count === 0) return
        const lastTime = xyyData.getNativeXValues().get(count - 1)

        // Clamp cursor to path's end time
        const path = key.substring(key.indexOf(':') + 1)
        const pathRange = this.pathTimeRanges.get(path)
        const maxCursorTime = pathRange ? Math.min(currentTime, pathRange.to) : currentTime

        if (maxCursorTime <= lastTime) return
        const lastTop = xyyData.getNativeYValues().get(count - 1)
        const lastBottom = xyyData.getNativeY1Values().get(count - 1)
        xyyData.append(maxCursorTime, lastTop, lastBottom)
        this.cursorKeys.add(key)
    }
}