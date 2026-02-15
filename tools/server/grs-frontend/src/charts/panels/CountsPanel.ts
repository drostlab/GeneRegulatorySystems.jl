import { EAxisAlignment, ENumericFormat,FastLineRenderableSeries,NumberRange,NumericAxis, XyDataSeries } from "scichart";
import { TimeseriesPanel } from "./TimeseriesPanel";
import type { BasePanelOptions } from "./BasePanel";
import type { TimeseriesData } from "@/types/simulation";
import { CHART_FONT_FAMILY, CHART_FONT_SIZES, AXIS_THICKNESS_NARROW } from "../chartConstants";


export class CountsPanel extends TimeseriesPanel {
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
                seriesCount++
            }
        }
        console.debug(`[CountsPanel] setData: created ${seriesCount} line series`)
    }
}
