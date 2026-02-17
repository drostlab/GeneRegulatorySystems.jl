import { BasePanel, type BasePanelOptions } from "./BasePanel";
import type { TimeseriesData, TimeseriesMetadata } from "@/types/simulation";


export type PathTimeRanges = Map<string, { from: number; to: number }>

export abstract class TimeseriesPanel extends BasePanel {
    protected metadata: TimeseriesMetadata | null = null
    protected pathTimeRanges: PathTimeRanges = new Map()

    constructor(options: BasePanelOptions) {
        super(options)
    }

    setMetadata(metadata: TimeseriesMetadata | null): void {
        this.metadata = metadata
    }

    setPathTimeRanges(ranges: PathTimeRanges): void {
        this.pathTimeRanges = ranges
    }

    abstract setData(timeseries: TimeseriesData): void

    /**
     * Append incremental streaming data to existing series.
     * Implementations should use appendRange for efficiency.
     *
     * @param timeseries - Incremental data points from the current time window
     * @param currentTime - Current simulation time (used for trailing cursor point)
     */
    abstract appendStreamingData(timeseries: TimeseriesData, currentTime: number): void
}
