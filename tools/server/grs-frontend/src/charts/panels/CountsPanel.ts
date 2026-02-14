import { EAxisAlignment, ENumericFormat,FastLineRenderableSeries,NumberRange,NumericAxis, XyDataSeries } from "scichart";
import { TimeseriesPanel } from "./TimeseriesPanel";
import type { BasePanelOptions } from "./BasePanel";
import type { TimeseriesData } from "@/types/simulation";


export class CountsPanel extends TimeseriesPanel {
    constructor(options: BasePanelOptions, title: string) {
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
            axisTitle: title,
            axisAlignment: EAxisAlignment.Left,
            labelFormat: ENumericFormat.Decimal,
            labelPrecision: 0,
            labelStyle: {fontSize: 10},
            axisTitleStyle: {fontSize: 12, fontFamily: "Arial"},
            drawMajorBands: false,
            drawMajorTickLines: false,
            drawMinorTickLines: false,
            growBy: new NumberRange(0.01, 0.01),
            majorGridLineStyle: { color: "#f5f5f5"},
            minorGridLineStyle: { color: "#f5f5f5"},
            axisThickness: 44
        })

        this.surface.xAxes.add(xAxis)
        this.surface.yAxes.add(yAxis)
    }

    setData(timeseries: TimeseriesData): void {
        this.clearData()
        if (!timeseries) {
            console.warn("no timeseries supplied")
            return
        }
        if (!this.metadata) {
            console.warn("trying to add timeseries when no metadata is available")
            return
        }
        
        for (const [species, pathData] of Object.entries(timeseries)) {
            for (const [path, series] of Object.entries(pathData)) {
                // create one line series per (species,segment)
                const geneId = this.metadata!.species_gene_mapping[species] ?? ""
                const colour = this.metadata.gene_colours[geneId] ?? "gray"
                const key = `${geneId}:${path}`
                const xySeries = new XyDataSeries(this.wasmContext, {
                    isSorted: true, 
                    containsNaN: false,
                    dataSeriesName: key
                })
                const time = series.map(pair => pair[0]); 
                const counts = series.map(pair => pair[1]); 
                xySeries.appendRange(time, counts)
                const lineSeries = new FastLineRenderableSeries(this.wasmContext, {
                     dataSeries: xySeries,
                     stroke: colour,
                     strokeThickness: 1,
                     isDigitalLine: true,
                     onHoveredChanged: sourceSeries => {
                        sourceSeries.strokeThickness = sourceSeries.isSelected ? 2 : 1
                     }
                })
                this.surface.renderableSeries.add(lineSeries)
            }
        }
    }
}
