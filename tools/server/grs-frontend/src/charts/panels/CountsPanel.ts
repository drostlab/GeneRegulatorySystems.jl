import { EAxisAlignment, ENumericFormat, FastLineRenderableSeries, NumberRange, NumericAxis, SweepAnimation, XyDataSeries } from "scichart";
import { TimeseriesPanel } from "./TimeseriesPanel";
import type { BasePanelOptions } from "./BasePanel";
import type { TimeseriesData } from "@/types/simulation";
import { getGeneFromSpeciesName } from "@/types/schedule";
import { CHART_FONT_FAMILY, CHART_FONT_SIZES, AXIS_THICKNESS_NARROW } from "../chartConstants";

const SWEEP_DURATION_MS = 400


export class CountsPanel extends TimeseriesPanel {
    /** Persistent data series map for streaming: `geneId:path` -> XyDataSeries */
    private seriesMap: Map<string, XyDataSeries> = new Map()

    /** Series keys that currently have a trailing cursor extension point */
    private cursorKeys: Set<string> = new Set()

    constructor(options: BasePanelOptions, title: string) {
        super(options)

        const xAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Time",
            labelStyle: {fontSize: CHART_FONT_SIZES.label},
            axisTitleStyle: {fontSize: CHART_FONT_SIZES.title, fontFamily: CHART_FONT_FAMILY},
            drawMajorBands: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false
        })

        const yAxis = new NumericAxis(this.wasmContext, {
            axisTitle: title,
            axisAlignment: EAxisAlignment.Left,
            labelFormat: ENumericFormat.Decimal,
            labelPrecision: 0,
            labelStyle: {fontSize: CHART_FONT_SIZES.label},
            axisTitleStyle: {fontSize: CHART_FONT_SIZES.title, fontFamily: CHART_FONT_FAMILY},
            drawMajorBands: false,
            drawMajorTickLines: false,
            drawMinorTickLines: false,
            growBy: new NumberRange(0.01, 0.01),
            majorGridLineStyle: { color: "#f5f5f5"},
            minorGridLineStyle: { color: "#f5f5f5"},
            axisThickness: AXIS_THICKNESS_NARROW
        })

        this.surface.xAxes.add(xAxis)
        this.surface.yAxes.add(yAxis)
    }

    override clearData(): void {
        this.seriesMap.clear()
        this.cursorKeys.clear()
        super.clearData()
    }

    setData(timeseries: TimeseriesData): void {
        this.clearData()
        if (!timeseries) {
            console.warn("[CountsPanel] no timeseries supplied")
            return
        }
        if (!this.metadata) {
            console.warn("[CountsPanel] trying to add timeseries when no metadata is available")
            return
        }

        let seriesCount = 0
        for (const [species, pathData] of Object.entries(timeseries)) {
            for (const [path, series] of Object.entries(pathData)) {
                const geneId = getGeneFromSpeciesName(species) ?? ""
                const colour = this.metadata.gene_colours[geneId] ?? "gray"
                const key = `${geneId}:${path}`
                const xySeries = new XyDataSeries(this.wasmContext, {
                    isSorted: true,
                    containsNaN: false,
                    dataSeriesName: key
                })
                const time = series.map(pair => pair[0])
                const counts = series.map(pair => pair[1])
                xySeries.appendRange(time, counts)
                this.seriesMap.set(key, xySeries)

                const coordinator = this.coordinator
                const lineSeries = new FastLineRenderableSeries(this.wasmContext, {
                    dataSeries: xySeries,
                    stroke: colour,
                    strokeThickness: 1,
                    isDigitalLine: true,
                    animation: new SweepAnimation({ duration: SWEEP_DURATION_MS }),
                    onHoveredChanged: sourceSeries => {
                        coordinator.syncHover(sourceSeries)
                    }
                })
                this.surface.renderableSeries.add(lineSeries)
                seriesCount++
            }
        }
        console.debug(`[CountsPanel] setData: created ${seriesCount} line series`)
    }

    appendStreamingData(timeseries: TimeseriesData, currentTime: number): void {
        if (!this.metadata) return

        for (const [species, pathData] of Object.entries(timeseries)) {
            for (const [path, points] of Object.entries(pathData)) {
                const geneId = getGeneFromSpeciesName(species) ?? ""
                const key = `${geneId}:${path}`

                let xySeries = this.seriesMap.get(key)
                if (!xySeries) {
                    // First data for this series during streaming -- create it
                    xySeries = this._createStreamingSeries(key, geneId)
                }

                // Remove trailing cursor point before appending real data
                this._removeCursorPoint(key, xySeries)

                // Append real data
                const time = points.map(p => p[0])
                const counts = points.map(p => p[1])
                xySeries.appendRange(time, counts)

                // Add new cursor point at current simulation time
                this._addCursorPoint(key, xySeries, currentTime)
            }
        }
    }

    /** Create a new XyDataSeries + FastLineRenderableSeries for a streaming key. */
    private _createStreamingSeries(key: string, geneId: string): XyDataSeries {
        const colour = this.metadata!.gene_colours[geneId] ?? "gray"
        const xySeries = new XyDataSeries(this.wasmContext, {
            isSorted: true,
            containsNaN: false,
            dataSeriesName: key
        })
        this.seriesMap.set(key, xySeries)

        const coordinator = this.coordinator
        const lineSeries = new FastLineRenderableSeries(this.wasmContext, {
            dataSeries: xySeries,
            stroke: colour,
            strokeThickness: 1,
            isDigitalLine: true,
            onHoveredChanged: sourceSeries => {
                coordinator.syncHover(sourceSeries)
            }
        })
        this.surface.renderableSeries.add(lineSeries)
        return xySeries
    }

    /** Remove the trailing cursor extension point if present. */
    private _removeCursorPoint(key: string, xySeries: XyDataSeries): void {
        if (!this.cursorKeys.has(key)) return
        const count = xySeries.count()
        if (count > 0) {
            xySeries.removeRange(count - 1, 1)
        }
        this.cursorKeys.delete(key)
    }

    /** Add a trailing cursor point at currentTime with the last known value. */
    private _addCursorPoint(key: string, xySeries: XyDataSeries, currentTime: number): void {
        const count = xySeries.count()
        if (count === 0) return
        const lastValue = xySeries.getNativeYValues().get(count - 1)
        const lastTime = xySeries.getNativeXValues().get(count - 1)

        // Clamp cursor to path's end time (don't extend into later segments)
        const path = key.substring(key.indexOf(':') + 1)
        const pathRange = this.pathTimeRanges.get(path)
        const maxCursorTime = pathRange ? Math.min(currentTime, pathRange.to) : currentTime

        if (maxCursorTime > lastTime) {
            xySeries.append(maxCursorTime, lastValue)
            this.cursorKeys.add(key)
        }
    }
}
