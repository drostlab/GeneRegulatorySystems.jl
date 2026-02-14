import { EAxisAlignment, NumericAxis } from "scichart";
import { BasePanel, type BasePanelOptions } from "./BasePanel";


export class TimelinePanel extends BasePanel {
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
            axisTitle: "Schedule Timeline",
            axisAlignment: EAxisAlignment.Left,
            axisTitleStyle: {fontSize: 12, fontFamily: "Arial"},
            drawMajorBands: false,
            drawLabels: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false,
            drawMajorTickLines: false,
            drawMinorTickLines: false,
            axisThickness: 50
        })

        this.surface.xAxes.add(xAxis)
        this.surface.yAxes.add(yAxis)
    }
}