import { EAxisAlignment, FastBandRenderableSeries, NumericAxis, XyyDataSeries } from "scichart";
import { TimeseriesPanel } from "./TimeseriesPanel";
import type { BasePanelOptions } from "./BasePanel";
import type { TimeseriesData } from "@/types/simulation";
import { restructureTimeseriesByPathAndGene } from "@/types/simulation";


export class PromoterPanel extends TimeseriesPanel {
    constructor(options: BasePanelOptions) {
        super(options)

        const xAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Time",
            labelStyle: {fontSize: 10},
            axisTitleStyle: {fontSize: 12, fontFamily: "Arial"},
            drawMajorBands: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false
        })
        
        const yAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Promoter Activity",
            axisAlignment: EAxisAlignment.Left,
            axisTitleStyle: {fontSize: 12, fontFamily: "Arial"},
            drawMajorBands: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false,
            drawMajorTickLines: false,
            drawMinorTickLines: false,
            drawLabels: false,
            axisThickness: 50
        })

        this.surface.xAxes.add(xAxis)
        this.surface.yAxes.add(yAxis)
    }

    setData(timeseries: TimeseriesData): void {
        this.clearData()
        if (!timeseries || !this.metadata) return

        const dataByPath = restructureTimeseriesByPathAndGene(timeseries, this.metadata)

        // Assign track index to each path (for vertical stacking of paths)
        const sortedPaths = Object.keys(dataByPath).sort()
        const pathToTrackIndex = new Map<string, number>()
        sortedPaths.forEach((path, index) => {
            pathToTrackIndex.set(path, index)
        })

        for (const [path, geneData] of Object.entries(dataByPath)) {
            const sortedGenes = Object.keys(geneData).sort()
            const genesCount = sortedGenes.length
            const bandHeight = 1.0 / genesCount
            const baseY = pathToTrackIndex.get(path) ?? 0

            sortedGenes.forEach((geneId, geneIndex) => {
                const { colour, series } = geneData[geneId]!
                const yCenter = baseY + geneIndex * bandHeight + 0.5 * bandHeight

                // Build step function: emit old value at transition, then new value
                const xData: number[] = []
                const yTop: number[] = []
                const yBottom: number[] = []

                for (let i = 0; i < series.length; i++) {
                    const [time, state] = series[i]!
                    
                    // Emit previous state at transition time
                    if (i > 0) {
                        const prevState = series[i - 1]![1]
                        const halfHeight = 0.5 * bandHeight * prevState
                        xData.push(time)
                        yTop.push(yCenter + halfHeight)
                        yBottom.push(yCenter - halfHeight)
                    }
                    
                    // Emit new state
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

                const bandSeries = new FastBandRenderableSeries(this.wasmContext, {
                    dataSeries: xyyDataSeries,
                    stroke: colour,
                    strokeThickness: 0.0,
                    fillY1: colour,
                    strokeY1: colour
                })
                this.surface.renderableSeries.add(bandSeries)
            })
        }
    }
}