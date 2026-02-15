import { EAxisAlignment, FastBandRenderableSeries, NumericAxis, XyyDataSeries } from "scichart"
import { TimeseriesPanel } from "./TimeseriesPanel"
import type { BasePanelOptions } from "./BasePanel"
import type { TimeseriesData } from "@/types/simulation"
import { restructureTimeseriesByPathAndGene } from "@/types/simulation"
import { CHART_FONT_FAMILY, CHART_FONT_SIZES, AXIS_THICKNESS } from "../chartConstants"

export type PathYRanges = Map<string, { yMin: number; yMax: number }>

export class PromoterPanel extends TimeseriesPanel {
    private pathYRanges: PathYRanges = new Map()

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
    }

    setData(timeseries: TimeseriesData): void {
        this.clearData()
        if (!timeseries || !this.metadata) return

        const dataByPath = restructureTimeseriesByPathAndGene(timeseries, this.metadata)
        console.debug(`[PromoterPanel] setData: ${Object.keys(dataByPath).length} paths in data, ${this.pathYRanges.size} paths in yRanges`)
        console.debug(`[PromoterPanel]   data paths: [${Object.keys(dataByPath)}]`)
        console.debug(`[PromoterPanel]   yRange paths: [${[...this.pathYRanges.keys()]}]`)

        for (const [path, geneData] of Object.entries(dataByPath)) {
            const yRange = this.pathYRanges.get(path)
            if (!yRange) {
                console.debug(`[PromoterPanel]   skipping path '${path}' - no yRange found`)
                continue
            }

            const sortedGenes = Object.keys(geneData).sort()
            const genesCount = sortedGenes.length
            const bandHeight = (yRange.yMax - yRange.yMin) / genesCount

            sortedGenes.forEach((geneId, geneIndex) => {
                const { colour, series } = geneData[geneId]!
                const yCenter = yRange.yMin + geneIndex * bandHeight + 0.5 * bandHeight

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

                const xyyDataSeries = new XyyDataSeries(this.wasmContext, {
                    isSorted: true,
                    containsNaN: false,
                    dataSeriesName: `${geneId}:${path}`
                })
                if (xData.length > 0) {
                    xyyDataSeries.appendRange(xData, yTop, yBottom)
                }

                const coordinator = this.coordinator
                const bandSeries = new FastBandRenderableSeries(this.wasmContext, {
                    dataSeries: xyyDataSeries,
                    stroke: colour,
                    strokeThickness: 0.0,
                    fillY1: colour,
                    strokeY1: colour,
                    onHoveredChanged: (sourceSeries) => {
                        coordinator.syncHover(sourceSeries)
                    }
                })
                this.surface.renderableSeries.add(bandSeries)
            })
        }
    }
}