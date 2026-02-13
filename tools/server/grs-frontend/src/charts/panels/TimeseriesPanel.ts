import { BasePanel, type BasePanelOptions } from "./BasePanel";
import type { TimeseriesData, TimeseriesMetadata } from "@/types/simulation";


export abstract class TimeseriesPanel extends BasePanel {
    protected metadata: TimeseriesMetadata | null = null

    constructor(options: BasePanelOptions) {
        super(options)
    }

    setMetadata(metadata: TimeseriesMetadata | null): void {
        this.metadata = metadata
    }

    abstract setData(timeseries: TimeseriesData): void

    clearData(): void {
        this.surface.renderableSeries.clear()
    }
}
