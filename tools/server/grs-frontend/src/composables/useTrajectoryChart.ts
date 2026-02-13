/**
 * useTrajectoryChart - Composable for managing gene trajectory visualization
 *
 * API:
 * - initChart(containerRef) - Initialize chart with 3 stacked axes
 * - updateTrajectory(timeseries, geneColours) - Render or update all tracks
 * - clearChart() - Remove all series (for loading new result)
 * - dispose() - Cleanup resources
 *
 */

import type { Ref } from 'vue'
import type { TrackSeriesData } from '@/types'
import type { ScheduleSegmentDisplay } from '@/types/schedule'
import {
    SciChartSurface,
    NumericAxis,
    FastLineRenderableSeries,
    FastBandRenderableSeries,
    XyDataSeries,
    XyyDataSeries,
    EAxisAlignment,
    EAutoRange,
    NumberRange,
    ENumericFormat,
    LeftAlignedOuterVerticallyStackedAxisLayoutStrategy,
    EWatermarkPosition,
    XyScatterRenderableSeries,
    EllipsePointMarker,
    RolloverModifier,
    CursorModifier,
    MouseWheelZoomModifier,
    ZoomPanModifier,
    ZoomExtentsModifier,
    EXyDirection
} from 'scichart'

/**
 * Custom RolloverModifier that only shows tooltip for the nearest series
 * and customizes tooltip content to show only gene/path info
 */
class NearestPointRolloverModifier extends RolloverModifier {
    protected CalculateTooltipPositions(
        tooltipArray: any[],
        _allowTooltipOverlapping: boolean,
        spacing: number,
        seriesViewRect: any,
        pixelRatio: number,
        isVerticalChart: boolean = false
    ): any[] {
        const allTooltips = super.CalculateTooltipPositions(
            tooltipArray,
            true,
            spacing,
            seriesViewRect,
            pixelRatio,
            isVerticalChart
        )

        if (allTooltips.length === 0) return []

        let min = Number.MAX_SAFE_INTEGER
        let nearestTooltip: any = null
        allTooltips.forEach((tooltip: any) => {
            if (tooltip.seriesInfo.distance < min) {
                min = tooltip.seriesInfo.distance
                nearestTooltip = tooltip
            }
        })

        return nearestTooltip ? [nearestTooltip] : []
    }
}

/**
 * Custom tooltip data template - shows gene, path, and track type with count on separate lines
 */
function tooltipDataTemplate(seriesInfo: any): string[] {
    const seriesName = seriesInfo.seriesName || 'Unknown'
    
    // Handle schedule segments: format "label (path) [schedule]"
    const scheduleMatch = seriesName.match(/^(.+?)\s*\((.+?)\)\s*\[schedule\]$/)
    if (scheduleMatch) {
        const label = scheduleMatch[1]
        const path = scheduleMatch[2]
        return [`${label}`, `Path ${path}`]
    }
    
    // Handle simulation tracks: format "geneId (path) [trackKind]"
    const match = seriesName.match(/^(.+?)\s*\((.+?)\)\s*\[(.+?)\]$/)
    if (match) {
        const geneId = match[1]
        const path = match[2]
        const trackKind = match[3]
        const yValue = seriesInfo.yValue !== undefined ? seriesInfo.yValue : null
        
        // Format track info with natural language
        let trackInfo = ''
        if (trackKind.toLowerCase() === 'promoter') {
            trackInfo = `Promoter Active`
        } else {
            // For mRNA and Protein, show count with natural pluralization
            const count = Math.round(yValue)
            const trackLabels: Record<string, string> = {
                mrna: 'mRNA',
                protein: 'Protein'
            }
            const trackLabel = trackLabels[trackKind.toLowerCase()] || trackKind
            const plural = count !== 1 ? 's' : ''
            trackInfo = `${count} ${trackLabel}${plural}`
        }
        
        return [`Gene ${geneId}`, `Path ${path}`, trackInfo]
    }
    return [seriesName]
}

/**
 * Lighten a hex colour by a percentage
 */
function lightenColor(hex: string, percent: number = 50): string {
    const num = parseInt(hex.replace('#', ''), 16)
    const r = Math.min(255, Math.round((num >> 16) + (255 - (num >> 16)) * (percent / 100)))
    const g = Math.min(255, Math.round(((num >> 8) & 0x00FF) + (255 - ((num >> 8) & 0x00FF)) * (percent / 100)))
    const b = Math.min(255, Math.round((num & 0x0000FF) + (255 - (num & 0x0000FF)) * (percent / 100)))
    return `#${((r << 16) | (g << 8) | b).toString(16).padStart(6, '0')}`
}

// Track configuration (hardcoded for gene regulatory systems)
const TRACK_CONFIG = {
    schedule: {
        axisId: 'scheduleAxis',
        title: 'Schedule Timeline',
        strokeThickness: 2,
        renderType: 'line' as const
    },
    promoter: {
        axisId: 'promoterAxis',
        title: 'Promoter Activity',
        strokeThickness: 2,
        renderType: 'band' as const
    },
    mrna: {
        axisId: 'mrnaAxis',
        title: 'mRNA Count',
        strokeThickness: 2,
        renderType: 'line' as const
    },
    protein: {
        axisId: 'proteinAxis',
        title: 'Protein Count',
        strokeThickness: 2,
        renderType: 'line' as const
    }
} as const

// Derive track kinds from config (single source of truth)
type TrackKind = keyof typeof TRACK_CONFIG

export function useTrajectoryChart() {
    // =====================================================================
    // STATE
    // =====================================================================

    let sciChartSurface: any = null
    let wasmContext: any = null
    let currentTheme: any = null
    let loaderElement: HTMLElement | null = null

    // Series storage: track → geneId → renderableSeries
    // Use plain Maps (not Vue refs) to avoid reactive proxy issues with WASM objects
    const sciChartSeries = new Map<string, Map<string, any>>()
    // Track point counts per series to avoid dataSeries.count() binding issues
    const seriesPointCounts = new Map<string, Map<string, number>>()
    // Hover state: currently hovered (geneId:path) key
    let hoveredSeriesKey: string | null = null
    // Store original series properties for restoring after hover
    const originalSeriesProps = new Map<any, { opacity: number; strokeThickness: number; stroke?: string; fill?: string }>()
    // Callback for timepoint changes (for syncing with viewer store)
    let onTimepointChangeCallback: ((timepoint: number) => void) | null = null

    async function createTheme() {
        const isDarkMode = document.documentElement.classList.contains('app-dark')
        const { SciChartJSDarkv2Theme } = await import('scichart/Charting/Themes/SciChartJSDarkv2Theme')
        const { SciChartJSLightTheme } = await import('scichart/Charting/Themes/SciChartJSLightTheme')
        currentTheme = isDarkMode ? new SciChartJSDarkv2Theme() : new SciChartJSLightTheme()
        return currentTheme
    }

    // =====================================================================
    // INITIALIZATION
    // =====================================================================

    /**
     * Initialize SciChart surface with 3 vertically stacked Y-axes
     */
    async function initChart(containerRef: Ref<HTMLDivElement | undefined>, enabledTracks?: Set<string>): Promise<void> {
        console.log('[initChart] Starting initialization')
        console.log('[initChart] containerRef.value:', containerRef.value)
        console.log('[initChart] containerRef.value size:', containerRef.value?.clientWidth, 'x', containerRef.value?.clientHeight)
        
        if (!containerRef.value) {
            throw new Error('Container reference is required to initialize chart')
        }

        if (sciChartSurface) {
            console.warn('[useTrajectoryChart] Chart already initialized')
            return
        }

        // Use provided tracks or default to all enabled
        const tracksToEnable = enabledTracks ?? new Set(['schedule', 'promoter', 'mrna', 'protein'])

        try {

            const theme = await createTheme()

            // Create surface
            console.log('[initChart] Creating SciChartSurface...')
            const { sciChartSurface: surface, wasmContext: context } = await SciChartSurface.create(
                containerRef.value,
                { theme }
            )
            sciChartSurface = surface
            wasmContext = context
            console.log('[initChart] SciChartSurface created successfully')

            // Ensure layout manager is initialized before proceeding
            await new Promise(resolve => setTimeout(resolve, 50))

            // Register Montserrat font from local public folder
            try {
                await sciChartSurface.registerFont(
                    'Montserrat',
                    '/Montserrat-Regular.ttf'
                )
            } catch (fontErr) {
                console.warn('[useTrajectoryChart] Failed to register Montserrat font:', fontErr)
            }

            sciChartSurface.watermarkPosition = EWatermarkPosition.TopRight

            // X-axis (shared)
            const xAxis = new NumericAxis(wasmContext, {
                axisAlignment: EAxisAlignment.Bottom,
                autoRange: EAutoRange.Never,
                labelStyle: {
                    fontSize: 12,
                    fontFamily: 'Arial'
                }
            })
            sciChartSurface.xAxes.add(xAxis)

            // Y-axes for all possible tracks (so they can be dynamically shown/hidden)
            // but only visible if track is enabled
            const trackKinds = Object.keys(TRACK_CONFIG) as TrackKind[]
            for (let trackIndex = 0; trackIndex < trackKinds.length; trackIndex++) {
                const trackKind = trackKinds[trackIndex]
                const trackConfig = TRACK_CONFIG[trackKind]
                const isFirstTrack = trackIndex === 0  // topmost track (schedule)
                
                // Determine separator line colour based on theme
                const isDarkMode = document.documentElement.classList.contains('app-dark')
                const separatorColor = isDarkMode ? '#444444' : '#d0d0d0'
                
                const borderConfig: any = {}
                if (isFirstTrack) {
                    // Topmost track: add both top and bottom borders
                    borderConfig.borderTop = 1
                    borderConfig.borderTopBrush = separatorColor
                    borderConfig.borderBottom = 1
                    borderConfig.borderBottomBrush = separatorColor
                } else {
                    // Other tracks: bottom border only (shared with track above)
                    borderConfig.borderBottom = 1
                    borderConfig.borderBottomBrush = separatorColor
                }
                
                const axis = new NumericAxis(wasmContext, {
                    id: trackConfig.axisId,
                    axisAlignment: EAxisAlignment.Left,
                    autoRange: EAutoRange.Always,
                    labelFormat: ENumericFormat.Decimal,
                    labelPrecision: 0,
                    axisTitle: trackConfig.title,
                    axisTitleStyle: {
                        fontSize: 16,
                        fontFamily: 'Arial',
                    },
                    labelStyle: {
                        fontSize: 12,
                        fontFamily: 'Arial'
                    },
                    flippedCoordinates: trackKind === 'promoter',  // Reverse Y-axis for promoter
                    isVisible: tracksToEnable.has(trackKind),  // Hide axis if track not enabled initially
                    border: borderConfig,
                    drawMajorBands: false
                })
                
                // Hide tick labels for promoter track and schedule track
                if (trackKind === 'promoter' || trackKind === 'schedule') {
                    axis.drawLabels = false
                    axis.drawMajorGridLines = false
                    axis.drawMinorGridLines = false
                } else {
                    // Add subtle grid for simulation tracks
                    axis.drawMajorGridLines = true
                    axis.drawMinorGridLines = false
                }
                
                sciChartSurface.yAxes.add(axis)
                sciChartSeries.set(trackKind, new Map())
                seriesPointCounts.set(trackKind, new Map())
            }

            // Apply vertical stacking layout
            if (!sciChartSurface.layoutManager) {
                throw new Error('[useTrajectoryChart] layoutManager not initialized on sciChartSurface')
            }
            sciChartSurface.layoutManager.leftOuterAxesLayoutStrategy =
                new LeftAlignedOuterVerticallyStackedAxisLayoutStrategy()

            // Add interactivity modifiers
            const rolloverModifier = new NearestPointRolloverModifier({
                showTooltip: true,
                showRolloverLine: true,
                showAxisLabel: true,
                hitTestRadius: 100000,  // Large number to detect across whole viewport
                tooltipDataTemplate: tooltipDataTemplate
            })
            
            // Style rollover line (vertical cursor) and tooltips
            ;(rolloverModifier as any).rolloverLineStroke = '#555555'
            ;(rolloverModifier as any).tooltipFill = '#444444'
            ;(rolloverModifier as any).tooltipStroke = '#FFFFFF'
            ;(rolloverModifier as any).axisLabelFill = '#FFFFFF'
            ;(rolloverModifier as any).axisLabelStroke = '#000000'
            ;(rolloverModifier as any).axisLabelBackground = '#000000'
            ;(rolloverModifier as any).rolloverAxisLabelBackground = '#000000'
            
            sciChartSurface.domCanvas2D.addEventListener('mousemove', (e: MouseEvent) => {
                handleMouseMove(e)
            })
            
            sciChartSurface.chartModifiers.add(rolloverModifier)
            sciChartSurface.chartModifiers.add(
                new MouseWheelZoomModifier({ xyDirection: EXyDirection.XDirection })
            )
            sciChartSurface.chartModifiers.add(
                new ZoomPanModifier({ xyDirection: EXyDirection.XDirection })
            )
            sciChartSurface.chartModifiers.add(
                new ZoomExtentsModifier()
            )
            
            // Add CursorModifier for the X-axis label with black background
            const cursorModifier = new CursorModifier({
                axisLabelFill: '#000000'
            })
            sciChartSurface.chartModifiers.add(cursorModifier)
            
            // Add mouse move listener to sync timepoint with viewer store
            const canvasElement = sciChartSurface.domCanvas2D
            if (canvasElement) {
                canvasElement.addEventListener('mousemove', (e: MouseEvent) => {
                    try {
                        const rect = canvasElement.getBoundingClientRect()
                        const mouseX = e.clientX - rect.left
                        const xAxis = sciChartSurface.xAxes.get(0)
                        if (xAxis && onTimepointChangeCallback) {
                            // Convert pixel position to data value using SciChart's CoordinateCalculator
                            const coordCalculator = xAxis.getCurrentCoordinateCalculator()
                            const dataValue = coordCalculator.getDataValue(mouseX)
                            if (isFinite(dataValue)) {
                                onTimepointChangeCallback(dataValue)
                            }
                        }
                    } catch (err) {
                        // Silently ignore errors during mouse move (axis might not be ready)
                    }
                })
            }
        } catch (err) {
            console.error('[useTrajectoryChart] Failed to initialize chart:', err)
            throw err
        }
    }

    // =====================================================================
    // RENDERING
    // =====================================================================

    /**
     * Render or update trajectory from pre-converted track data
     * Handles both initial creation and streaming updates
     */
    function updateTrajectory(trackData: Record<string, TrackSeriesData[]>, enabledTracks?: Set<string>): void {
        console.log('[updateTrajectory] Entry point - trackData keys:', Object.keys(trackData))
        for (const [kind, tracks] of Object.entries(trackData)) {
            console.log(`[updateTrajectory] ${kind}: ${tracks.length} tracks`)
        }
        console.log('[updateTrajectory] enabledTracks:', enabledTracks)
        
        if (!sciChartSurface || !wasmContext) {
            console.warn('[useTrajectoryChart] Chart not initialized - cannot update trajectory')
            return
        }

        // Use provided tracks or default to all enabled
        const tracksToEnable = enabledTracks ?? new Set(['schedule', 'promoter', 'mrna', 'protein'])
        console.log('[updateTrajectory] tracksToEnable:', tracksToEnable)

        try {
            // Calculate data bounds for X-axis limits
            let minX = Infinity
            let maxX = -Infinity
            
            for (const tracks of Object.values(trackData)) {
                for (const track of tracks) {
                    if (track.xData.length > 0) {
                        const trackMin = Math.min(...track.xData)
                        const trackMax = Math.max(...track.xData)
                        minX = Math.min(minX, trackMin)
                        maxX = Math.max(maxX, trackMax)
                    }
                }
            }

            console.log('[updateTrajectory] X-axis bounds: minX=', minX, 'maxX=', maxX)

            // Update each track that exists in the data and is enabled
            for (const [trackKind, tracks] of Object.entries(trackData)) {
                console.log(`[updateTrajectory] Processing ${trackKind}: ${tracks.length} tracks, enabled=${tracksToEnable.has(trackKind)}`)
                if (!tracksToEnable.has(trackKind)) {
                    console.log(`[updateTrajectory] Skipping ${trackKind} - not enabled`)
                    continue  // Skip disabled tracks
                }
                if (tracks.length > 0) {
                    console.log(`[updateTrajectory] Updating ${trackKind} with ${tracks.length} series`)
                    updateTrack(trackKind as TrackKind, tracks)
                }
            }

            // Set X-axis limits to prevent panning/zooming beyond data
            if (isFinite(minX) && isFinite(maxX)) {
                const xAxis = sciChartSurface.xAxes.get(0)
                if (xAxis) {
                    const padding = (maxX - minX) * 0.03
                    xAxis.visibleRangeLimit = new NumberRange(
                        minX - padding,
                        maxX + padding
                    )
                }
            }

            console.log('[updateTrajectory] Calling zoomExtents()')
            // Auto-fit view
            sciChartSurface.zoomExtents()
        } catch (err) {
            console.error('[useTrajectoryChart] Failed to update trajectory:', err)
            throw err
        }
    }

    /**
     * Update a single track (mRNA, protein, or promoter)
     * Creates new series on first render, appends to existing on updates
     */
    function updateTrack(trackKind: TrackKind, trackData: TrackSeriesData[]): void {
        if (trackData.length === 0) return

        const trackSeriesMap = sciChartSeries.get(trackKind)
        if (!trackSeriesMap) return

        const config = TRACK_CONFIG[trackKind]

        // Check if this is first render or update
        if (trackSeriesMap.size === 0) {
            // First render - create new series
            for (const track of trackData) {
                createSeries(trackKind, track, config, trackData)
            }
        } else {
            // Update - append new points to existing series
            for (const track of trackData) {
                appendToSeries(trackKind, track)
            }
        }
    }

    /**
     * Handle mouse move - detect series hover, dim others, highlight hovered
     */
    function handleMouseMove(e: MouseEvent): void {
        if (!sciChartSurface) return

        // Get mouse coordinates relative to the chart
        const rect = sciChartSurface.domCanvas2D.getBoundingClientRect()
        const mouseX = e.clientX - rect.left
        const mouseY = e.clientY - rect.top
        
        // Find which series is under the mouse
        let newHoveredKey: string | null = null
        for (const [, trackMap] of sciChartSeries.entries()) {
            for (const [seriesKey, seriesArray] of trackMap.entries()) {
                const series = Array.isArray(seriesArray) ? seriesArray : [seriesArray]
                for (const s of series) {
                    if (s.hitTestProvider) {
                        const hitTest = s.hitTestProvider.hitTest({ x: mouseX, y: mouseY }, 10)
                        if (hitTest && hitTest.isHit) {
                            newHoveredKey = seriesKey
                            break
                        }
                    }
                }
                if (newHoveredKey) break
            }
            if (newHoveredKey) break
        }

        // Only update if hover changed
        if (newHoveredKey !== hoveredSeriesKey) {
            if (newHoveredKey) {
                highlightSeries(newHoveredKey)
            } else {
                restoreAllSeries()
            }
            hoveredSeriesKey = newHoveredKey
        }
    }

    /**
     * Highlight a series by key, dim others (including other genes)
     */
    function highlightSeries(targetKey: string): void {
        // Extract target gene ID from key format "geneId:path"
        const targetGeneId = targetKey.split(':')[0]
        
        sciChartSeries.forEach((trackMap) => {
            trackMap.forEach((seriesArray, seriesKey) => {
                const seriesGeneId = seriesKey.split(':')[0]
                const isTargetGene = seriesGeneId === targetGeneId
                const series = Array.isArray(seriesArray) ? seriesArray : [seriesArray]
                
                series.forEach(s => {
                    // Store original properties if not already stored
                    if (!originalSeriesProps.has(s)) {
                        originalSeriesProps.set(s, {
                            opacity: s.opacity ?? 1.0,
                            strokeThickness: s.strokeThickness ?? 2,
                            stroke: s.stroke,
                            fill: s.fill
                        })
                    }

                    if (isTargetGene) {
                        // Highlight: lighten colour, increase thickness, full opacity
                        s.opacity = 1.0
                        if (s.stroke) {
                            s.stroke = lightenColor(s.stroke, 50)
                        }
                        if (s.fill) {
                            s.fill = lightenColor(s.fill, 50)
                        }
                        if (s.strokeThickness !== undefined) {
                            s.strokeThickness = (originalSeriesProps.get(s)?.strokeThickness ?? 2) + 1
                        }
                    } else {
                        // Dim: reduce opacity
                        s.opacity = 0.25
                    }
                })
            })
        })
    }

    /**
     * Restore all series to original appearance
     */
    function restoreAllSeries(): void {
        originalSeriesProps.forEach((props, series) => {
            series.opacity = props.opacity
            if (series.strokeThickness !== undefined) {
                series.strokeThickness = props.strokeThickness
            }
            // Restore original stroke and fill colours
            if (props.stroke !== undefined) {
                series.stroke = props.stroke
            }
            if (props.fill !== undefined) {
                series.fill = props.fill
            }
        })
    }

    /**
     * Create a new series for a gene track
     */
    function createSeries(
        trackKind: TrackKind,
        track: TrackSeriesData,
        config: (typeof TRACK_CONFIG)[TrackKind],
        allTracksOfKind?: TrackSeriesData[]
    ): void {
        const renderableSeries: any[] = []

        if (config.renderType === 'band') {
            // Promoter: band rendering matching Julia inspect tool

            // Each gene gets a horizontal band where the band position represents the fraction
            // Count genes in this path from all track data available
            let genesInPathCount = 1
            let geneIndexInPath = 0
            
            if (allTracksOfKind) {
                // Use provided track data to count genes
                const genesInPath = new Set<string>()
                for (const t of allTracksOfKind) {
                    if (t.path === track.path) {
                        genesInPath.add(t.geneId)
                    }
                }
                const sortedGenesInPath = Array.from(genesInPath).sort()
                genesInPathCount = genesInPath.size
                geneIndexInPath = sortedGenesInPath.indexOf(track.geneId)
            }
            
            // Band positioning: trackIndex is the base y-position per execution path
            // genes within a path are stacked using proportional height
            const bandHeight = 1.0 / genesInPathCount
            const baseY = track.trackIndex  // Use trackIndex from track data
            const yCenter = baseY + geneIndexInPath * bandHeight + 0.5 * bandHeight

            // Build step function with explicit transitions to avoid zoom artifacts
            // For each segment: emit point at start, then transition point at end time
            const xData: number[] = []
            const yData: number[] = []
            const y1Data: number[] = []
            
            for (let i = 0; i < track.xData.length; i++) {
                const t = track.xData[i]
                const fraction = track.yData[i]
                if (t === undefined || fraction === undefined) continue
                
                // Clamp fraction to [0, 1] range
                const clampedFraction = Math.max(0, Math.min(1, fraction))
                const halfBandWidth = 0.5 * bandHeight * clampedFraction
                const yTop = yCenter + halfBandWidth
                const yBottom = yCenter - halfBandWidth
                
                // At transition time, add point with OLD value first (to hold previous segment)
                if (i > 0) {
                    const prevFraction = track.yData[i - 1]
                    if (prevFraction !== undefined) {
                        const clampedPrevFraction = Math.max(0, Math.min(1, prevFraction))
                        const prevHalfBandWidth = 0.5 * bandHeight * clampedPrevFraction
                        const prevYTop = yCenter + prevHalfBandWidth
                        const prevYBottom = yCenter - prevHalfBandWidth
                        xData.push(t)
                        yData.push(prevYTop)
                        y1Data.push(prevYBottom)
                    }
                }
                
                // Then add point with NEW value
                xData.push(t)
                yData.push(yTop)
                y1Data.push(yBottom)
            }

            // Extend band to segment end time if we have data points and segmentTo is beyond last data point
            if (xData.length > 0 && track.xData.length > 0) {
                const lastTrackTime = track.xData[track.xData.length - 1]
                if (lastTrackTime !== undefined && track.segmentTo > lastTrackTime) {
                    const lastFraction = track.yData[track.yData.length - 1]
                    if (lastFraction !== undefined) {
                        const clampedLastFraction = Math.max(0, Math.min(1, lastFraction))
                        const lastHalfBandWidth = 0.5 * bandHeight * clampedLastFraction
                        const lastYTop = yCenter + lastHalfBandWidth
                        const lastYBottom = yCenter - lastHalfBandWidth
                        xData.push(track.segmentTo)
                        yData.push(lastYTop)
                        y1Data.push(lastYBottom)
                    }
                }
            }

            const xyyDataSeries = new XyyDataSeries(wasmContext, {
                isSorted: true,
                containsNaN: false,
                dataSeriesName: `${track.geneId} (${track.path}) [${trackKind}]`
            })

            if (xData.length > 0) {
                xyyDataSeries.appendRange(xData, yData, y1Data)
            }

            const bandSeries = new FastBandRenderableSeries(wasmContext, {
                dataSeries: xyyDataSeries,
                fill: track.colour,
                stroke: track.colour,
                strokeThickness: 0.1,
                strokeY1: track.colour,
                yAxisId: config.axisId
            })
            renderableSeries.push(bandSeries)
        } else {
            // mRNA/Protein: line rendering (with markers for branch segments)
            const xyDataSeries = new XyDataSeries(wasmContext, {
                isSorted: true,
                containsNaN: false,
                dataSeriesName: `${track.geneId} (${track.path}) [${trackKind}]`
            })

            if (track.xData.length > 0) {
                xyDataSeries.appendRange(track.xData, track.yData)
            }

            const lineSeries = new FastLineRenderableSeries(wasmContext, {
                dataSeries: xyDataSeries,
                stroke: track.colour,
                strokeThickness: config.strokeThickness,
                isDigitalLine: true,
                yAxisId: config.axisId
            })
            renderableSeries.push(lineSeries)
        }

        // Store and add to surface
        const trackSeriesMap = sciChartSeries.get(trackKind)
        const seriesKey = `${track.geneId}:${track.path}`
        
        // Store all series for this track
        renderableSeries.forEach(series => {
            sciChartSurface.renderableSeries.add(series)
        })
        
        trackSeriesMap?.set(seriesKey, renderableSeries)
        
        // Track point count
        const pointCountsMap = seriesPointCounts.get(trackKind)
        pointCountsMap?.set(seriesKey, track.xData.length)
    }

    /**
     * Append new points to existing series (streaming update)
     */
    function appendToSeries(trackKind: TrackKind, track: TrackSeriesData): void {
        const trackSeriesMap = sciChartSeries.get(trackKind)
        if (!trackSeriesMap) return

        const seriesKey = `${track.geneId}:${track.path}`
        const renderableSeriesArray = trackSeriesMap.get(seriesKey)
        if (!renderableSeriesArray) return

        const pointCountsMap = seriesPointCounts.get(trackKind)
        if (!pointCountsMap) return

        const currentCount = pointCountsMap.get(seriesKey) ?? 0
        const config = TRACK_CONFIG[trackKind]

        // Only append points we don't already have
        if (track.xData.length > currentCount) {
            if (config.renderType === 'band') {
                // Promoter: recalculate band positions for new points
                if (renderableSeriesArray.length === 0) return

                // Calculate gene index within this specific path only
                const genesInPath = new Set<string>()
                trackSeriesMap.forEach((_, key) => {
                    const parts = key.split(':')
                    const geneId = parts[0]
                    const pathId = parts[1]
                    if (pathId === track.path && geneId) {
                        genesInPath.add(geneId)
                    }
                })
                const sortedGenesInPath = Array.from(genesInPath).sort()
                const geneIndexInPath = sortedGenesInPath.indexOf(track.geneId)
                const genesInPathCount = genesInPath.size
                const bandHeight = 1.0 / genesInPathCount
                const baseY = track.trackIndex
                const yCenter = baseY + geneIndexInPath * bandHeight + 0.5 * bandHeight

                const newXData: number[] = []
                const newYData: number[] = []
                const newY1Data: number[] = []

                for (let i = currentCount; i < track.xData.length; i++) {
                    const t = track.xData[i]
                    const fraction = track.yData[i]
                    if (t === undefined || fraction === undefined) continue
                    
                    const halfBandWidth = 0.5 * bandHeight * fraction
                    const yTop = yCenter + halfBandWidth
                    const yBottom = yCenter - halfBandWidth
                    
                    // At transition time, add point with OLD value first
                    if (i > currentCount) {
                        const prevFraction = track.yData[i - 1]
                        if (prevFraction !== undefined) {
                            const prevHalfBandWidth = 0.5 * bandHeight * prevFraction
                            const prevYTop = yCenter + prevHalfBandWidth
                            const prevYBottom = yCenter - prevHalfBandWidth
                            newXData.push(t)
                            newYData.push(prevYTop)
                            newY1Data.push(prevYBottom)
                        }
                    }
                    
                    // Then add point with NEW value
                    newXData.push(t)
                    newYData.push(yTop)
                    newY1Data.push(yBottom)
                }

                if (newXData.length > 0 && renderableSeriesArray[0]) {
                    renderableSeriesArray[0].dataSeries.appendRange(newXData, newYData, newY1Data)
                }
            } else {
                // mRNA/Protein: append to all series in array (line + scatter if dashed)
                const newXData = Array.from(track.xData.slice(currentCount))
                const newYData = Array.from(track.yData.slice(currentCount))
                if (newXData.length > 0) {
                    renderableSeriesArray.forEach((series: any) => {
                        series.dataSeries.appendRange(newXData, newYData)
                    })
                }
            }
            pointCountsMap.set(seriesKey, track.xData.length)
        }
    }

    // =====================================================================
    // CLEANUP
    // =====================================================================

    /**
     * Clear all series from the chart (when loading new result)
     */
    function clearChart(): void {
        if (!sciChartSurface) return

        try {
            let totalRemoved = 0
            sciChartSeries.forEach((trackMap) => {
                trackMap.forEach((seriesArray) => {
                    // seriesArray is now an array of renderable series
                    if (Array.isArray(seriesArray)) {
                        seriesArray.forEach(series => {
                            sciChartSurface.renderableSeries.remove(series)
                            series.delete()
                            totalRemoved++
                        })
                    } else {
                        // Fallback for single series
                        sciChartSurface.renderableSeries.remove(seriesArray)
                        seriesArray.delete()
                        totalRemoved++
                    }
                })
                trackMap.clear()
            })

            // Reset point counts
            seriesPointCounts.forEach((trackMap) => {
                trackMap.clear()
            })

            // Reset all Y-axis ranges
            sciChartSurface.yAxes.asArray().forEach((axis: any) => {
                axis.autoRange = EAutoRange.Always
            })

            // Invalidate and refresh the chart view
            sciChartSurface.invalidateElement()
        } catch (err) {
            console.error('[useTrajectoryChart] Failed to clear chart:', err)
            throw err
        }
    }

    /**
     * Dispose of chart resources
     */
    function dispose(): void {
        if (sciChartSurface) {
            try {
                clearChart()
                sciChartSurface.delete()
                sciChartSurface = null
                wasmContext = null
            } catch (err) {
                console.error('[useTrajectoryChart] Failed to dispose chart:', err)
            }
        }
    }

    /**
     * Show loading overlay with SciChart-themed spinner
     */
    function showLoader(containerRef: Ref<HTMLDivElement | undefined>): void {
        if (!containerRef.value || loaderElement) return

        const isDarkMode = document.documentElement.classList.contains('app-dark')
        const overlayBg = 'rgba(0, 0, 0, 0.1)'
        const cardBg = isDarkMode ? '#2a2a2a' : '#f5f5f5'
        const spinnerColor = isDarkMode ? '#888888' : '#666666'
        const textColor = isDarkMode ? '#cccccc' : '#666666'

        const loaderContainer = document.createElement('div')
        loaderContainer.style.position = 'absolute'
        loaderContainer.style.top = '0'
        loaderContainer.style.left = '0'
        loaderContainer.style.width = '100%'
        loaderContainer.style.height = '100%'
        loaderContainer.style.display = 'flex'
        loaderContainer.style.alignItems = 'center'
        loaderContainer.style.justifyContent = 'center'
        loaderContainer.style.zIndex = '1000'
        loaderContainer.style.backgroundColor = overlayBg
        loaderContainer.style.backdropFilter = 'blur(1px)'

        const spinnerDiv = document.createElement('div')
        spinnerDiv.style.display = 'flex'
        spinnerDiv.style.flexDirection = 'column'
        spinnerDiv.style.alignItems = 'center'
        spinnerDiv.style.justifyContent = 'center'
        spinnerDiv.style.padding = '2rem'
        spinnerDiv.style.borderRadius = '8px'
        spinnerDiv.style.backgroundColor = cardBg
        spinnerDiv.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.2)'

        const spinner = document.createElement('div')
        spinner.style.width = '40px'
        spinner.style.height = '40px'
        spinner.style.border = `3px solid ${spinnerColor}`
        spinner.style.borderTopColor = 'transparent'
        spinner.style.borderRadius = '50%'
        spinner.style.animation = 'spin 1s linear infinite'

        const text = document.createElement('div')
        text.textContent = 'Loading result...'
        text.style.marginTop = '0.75rem'
        text.style.fontSize = '0.875rem'
        text.style.color = textColor

        const style = document.createElement('style')
        style.textContent = `
            @keyframes spin {
                from { transform: rotate(0deg); }
                to { transform: rotate(360deg); }
            }
        `
        document.head.appendChild(style)

        spinnerDiv.appendChild(spinner)
        spinnerDiv.appendChild(text)
        loaderContainer.appendChild(spinnerDiv)
        containerRef.value.appendChild(loaderContainer)

        loaderElement = loaderContainer
    }

    /**
     * Hide loading overlay
     */
    function hideLoader(containerRef: Ref<HTMLDivElement | undefined>): void {
        if (loaderElement && containerRef.value?.contains(loaderElement)) {
            containerRef.value.removeChild(loaderElement)
            loaderElement = null
        }
    }

    // =====================================================================
    // PUBLIC API
    // =====================================================================

    /**
     * Register callback for timepoint changes (mouse move on chart)
     */
    function onTimepointChange(callback: (timepoint: number) => void): void {
        onTimepointChangeCallback = callback
    }

    /**
     * Render schedule segments on the schedule track
     * @param segments Schedule segment display data to render
     * @param enabledTracks Set of enabled tracks
     */
    function renderScheduleSegments(segments: ScheduleSegmentDisplay[], enabledTracks: Set<string>): void {
        if (!sciChartSurface || !wasmContext) {
            console.warn('[useTrajectoryChart] Chart not initialized - cannot render schedule segments')
            return
        }

        // Skip if schedule track is disabled
        if (!enabledTracks.has('schedule')) {
            return
        }

        try {
            // Get or create the schedule track series map
            if (!sciChartSeries.has('schedule')) {
                sciChartSeries.set('schedule', new Map())
                seriesPointCounts.set('schedule', new Map())
            }

            const scheduleSeriesMap = sciChartSeries.get('schedule')!
            const scheduleConfig = TRACK_CONFIG['schedule']
            const yAxis = sciChartSurface.yAxes.getById(scheduleConfig.axisId)

            if (!yAxis) {
                console.warn('[useTrajectoryChart] Schedule axis not found')
                return
            }

            // Clear existing schedule series
            scheduleSeriesMap.forEach((series) => {
                if (sciChartSurface.renderableSeries.contains(series)) {
                    sciChartSurface.renderableSeries.remove(series)
                }
            })
            scheduleSeriesMap.clear()

            // Group segments by path for combined rendering
            const segmentsByPath = new Map<string, ScheduleSegmentDisplay[]>()
            for (const segment of segments) {
                if (!segmentsByPath.has(segment.path)) {
                    segmentsByPath.set(segment.path, [])
                }
                segmentsByPath.get(segment.path)!.push(segment)
            }

            // Create one series per path
            for (const [path, pathSegments] of segmentsByPath.entries()) {
                const xData: number[] = []
                const yData: number[] = []

                // Sort segments by time
                const sorted = [...pathSegments].sort((a, b) => a.from - b.from)

                for (const segment of sorted) {
                    if (segment.isInstant) {
                        // Instant segment: vertical line with fixed height
                        xData.push(segment.from, segment.from)
                        yData.push(0, 0.3)
                    } else {
                        // Non-instant segment: horizontal line at path track level
                        xData.push(segment.from, segment.to)
                        yData.push(segment.trackIndex, segment.trackIndex)
                    }
                }

                if (xData.length === 0) continue

                // Use first segment's label for series name
                const firstLabel = sorted[0]?.label ?? ''
                const seriesName = `${firstLabel} (${path}) [schedule]`
                const colour = sorted[0]?.colour ?? '#999999'

                // Create data series
                const dataSeries = new XyDataSeries(wasmContext, {
                    dataSeriesName: seriesName,
                    containsNaN: false,
                    xValues: xData,
                    yValues: yData
                })

                // Create line series
                const lineSeries = new FastLineRenderableSeries(wasmContext, {
                    dataSeries,
                    stroke: colour,
                    strokeThickness: 3,
                    yAxisId: scheduleConfig.axisId,
                    isDigitalLine: false,
                    opacity: 0.8
                })

                // Add point markers for instant segments
                if (sorted.some(s => s.isInstant)) {
                    const markerSeries = new XyScatterRenderableSeries(wasmContext, {
                        dataSeries: new XyDataSeries(wasmContext, {
                            xValues: sorted
                                .filter(s => s.isInstant)
                                .map(s => s.from),
                            yValues: sorted
                                .filter(s => s.isInstant)
                                .map((_, i) => i * 0.15)
                        }),
                        pointMarker: new EllipsePointMarker(wasmContext, {
                            width: 8,
                            height: 8,
                            fill: colour,
                            stroke: colour,
                            strokeThickness: 1
                        }),
                        yAxisId: scheduleConfig.axisId,
                        opacity: 0.8
                    })
                    sciChartSurface.renderableSeries.add(markerSeries)
                }

                sciChartSurface.renderableSeries.add(lineSeries)
                scheduleSeriesMap.set(path, lineSeries)
                
                // Update point counts for schedule track
                const schedulePointCounts = seriesPointCounts.get('schedule')
                if (schedulePointCounts) {
                    schedulePointCounts.set(path, xData.length)
                }
            }

            // Auto-fit view to include schedule data
            sciChartSurface.zoomExtents()
        } catch (err) {
            console.error('[useTrajectoryChart] Failed to render schedule segments:', err)
            throw err
        }
    }

    /**
     * Update axis visibility when track visibility changes
     * Removes disabled axes from the surface so they don't take up space
     */
    function updateTrackVisibility(enabledTracks: Set<string>): void {
        if (!sciChartSurface) {
            console.warn('[useTrajectoryChart] Chart not initialized - cannot update visibility')
            return
        }

        for (const [trackKind, trackConfig] of Object.entries(TRACK_CONFIG)) {
            const axis = sciChartSurface.yAxes.getById(trackConfig.axisId)
            if (!axis) continue

            if (enabledTracks.has(trackKind)) {
                // Enable: make sure axis is visible and in the surface
                if (!sciChartSurface.yAxes.contains(axis)) {
                    sciChartSurface.yAxes.add(axis)
                }
                axis.isVisible = true
            } else {
                // Disable: remove from surface so it doesn't take space
                if (sciChartSurface.yAxes.contains(axis)) {
                    sciChartSurface.yAxes.remove(axis)
                }
            }
        }
    }

    return {
        initChart,
        updateTrajectory,
        clearChart,
        dispose,
        showLoader,
        hideLoader,
        onTimepointChange,
        renderScheduleSegments,
        updateTrackVisibility
    }
}
