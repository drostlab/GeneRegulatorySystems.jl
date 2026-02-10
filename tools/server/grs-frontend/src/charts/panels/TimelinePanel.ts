import { EAxisAlignment, NumericAxis } from "scichart";
import { BasePanel, type BasePanelOptions } from "./BasePanel";


export class TimelinePanel extends BasePanel {
    constructor(options: BasePanelOptions) {
        super(options)

        const xAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Time",
            labelStyle: {fontSize: 10},
            axisTitleStyle: {fontSize: 12, fontFamily: "Montserrat"},
            drawMajorBands: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false
        })
        
        const yAxis = new NumericAxis(this.wasmContext, {
            axisTitle: "Schedule",
            axisAlignment: EAxisAlignment.Right,
            axisTitleStyle: {fontSize: 12, fontFamily: "Montserrat"},
            drawMajorBands: false,
            drawLabels: false,
            drawMajorGridLines: false,
            drawMinorGridLines: false,
            drawMajorTickLines: false,
            drawMinorTickLines: false
        })

        this.surface.xAxes.add(xAxis)
        this.surface.yAxes.add(yAxis)
    }
}