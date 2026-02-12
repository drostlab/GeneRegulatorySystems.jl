import { EAxisAlignment, ENumericFormat,NumericAxis } from "scichart";
import { BasePanel, type BasePanelOptions } from "./BasePanel";


export class CountsPanel extends BasePanel {
    constructor(options: BasePanelOptions, title: string) {
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
            axisTitle: title,
            axisAlignment: EAxisAlignment.Left,
            labelFormat: ENumericFormat.Decimal,
            labelPrecision: 0,
            labelStyle: {fontSize: 10},
            axisTitleStyle: {fontSize: 12, fontFamily: "Montserrat"},
            drawMajorBands: false,
            axisThickness: 44
        })

        this.surface.xAxes.add(xAxis)
        this.surface.yAxes.add(yAxis)

    }
}