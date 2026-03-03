import { BasePanel, type BasePanelOptions } from "./BasePanel";
import { ECoordinateMode, LineAnnotation, type AnnotationBase } from "scichart";
import type { TimeseriesData, TimeseriesMetadata } from "@/types/simulation";

const BOUNDARY_STROKE_DASH = [4, 4]

export type PathTimeRanges = Map<string, { from: number; to: number }>

export abstract class TimeseriesPanel extends BasePanel {
    protected metadata: TimeseriesMetadata | null = null
    protected pathTimeRanges: PathTimeRanges = new Map()
    /** Segment boundary dashed line annotations. */
    private boundaryAnnotations: AnnotationBase[] = []

    constructor(options: BasePanelOptions) {
        super(options)
    }

    setMetadata(metadata: TimeseriesMetadata | null): void {
        this.metadata = metadata
    }

    setPathTimeRanges(ranges: PathTimeRanges): void {
        this.pathTimeRanges = ranges
    }

    /** Draw dashed vertical lines at segment boundary times. */
    setSegmentBoundaries(times: number[]): void {
        this.clearBoundaryAnnotations()
        for (const t of times) {
            const line = new LineAnnotation({
                x1: t, x2: t,
                y1: 1, y2: -0.7,
                yCoordinateMode: ECoordinateMode.Relative,
                stroke: this.theme.timeline.segmentBoundary,
                strokeThickness: 1,
                strokeDashArray: BOUNDARY_STROKE_DASH,
            })
            this.surface.annotations.add(line)
            this.boundaryAnnotations.push(line)
        }
        console.debug(`[TimeseriesPanel] Added ${times.length} segment boundary lines`)
    }

    /** Re-apply theme colours to boundary annotations. */
    override applyTheme(isDark: boolean): void {
        super.applyTheme(isDark)
        for (const ann of this.boundaryAnnotations) {
            if (ann instanceof LineAnnotation) {
                ann.stroke = this.theme.timeline.segmentBoundary
            }
        }
    }

    private clearBoundaryAnnotations(): void {
        for (const ann of this.boundaryAnnotations) {
            this.surface.annotations.remove(ann)
            ann.delete()
        }
        this.boundaryAnnotations = []
    }

    abstract setData(timeseries: TimeseriesData): void

    /**
     * Append incremental streaming data to existing series.
     * Implementations should use appendRange for efficiency.
     *
     * @param timeseries - Incremental data points from the current time window
     */
    abstract appendStreamingData(timeseries: TimeseriesData): void
}
