/**
 * Timeseries data structure
 * Maps species (symbol) → path → sorted array of (time, count) tuples
 */
export type TimeseriesData = Record<string, Record<string, Array<[number, number]>>>

/**
 * Metadata for timeseries visualization
 */
export interface TimeseriesMetadata {
    species_gene_mapping: Record<string, string>
    gene_colours: Record<string, string>
    time_extent: { min: number; max: number }
}

/**
 * Simulation status values - discriminated union for type safety
 */
export type SimulationStatus = 'running' | 'completed' | 'error'

/**
 * Simulation data container with timeseries
 */
export interface SimulationData {
    timeseries: TimeseriesData
}

/**
 * Result metadata - what the /results endpoint returns
 * Discriminator: data is null (frames not loaded)
 */
export interface SimulationResultMetadata {
    id: string
    created_at?: string
    schedule_name: string
    schedule_spec: string
    status: SimulationStatus
    frame_count: number
    error?: string
    data: null
}

/**
 * Full result - metadata + frames combined
 * Use isResultLoaded() type guard to narrow from metadata to this type
 */
export interface SimulationResult extends Omit<SimulationResultMetadata, 'data'> {
    data: SimulationData
}

/**
 * Type guard to check if result has been fully loaded with timeseries data
 */
export function isResultLoaded(result: SimulationResultMetadata | SimulationResult): result is SimulationResult {
    return result.data !== null
}

/**
 * Get maximum time across all timeseries
 */
export function getMaxTime(timeseries: TimeseriesData): number {
    let maxTime = 0
    for (const pathData of Object.values(timeseries)) {
        for (const series of Object.values(pathData)) {
            for (const [t] of series) {
                maxTime = Math.max(maxTime, t)
            }
        }
    }
    return maxTime
}

/**
 * Restructure timeseries from species→path to path→gene format
 * Useful for rendering where you want to group genes per path
 * 
 * @param timeseries Original species → path → data structure
 * @param metadata Contains species→gene and gene→colour mappings
 * @returns path → gene → {geneId, colour, series}
 */
export function restructureTimeseriesByPathAndGene(
    timeseries: TimeseriesData,
    metadata: TimeseriesMetadata
): Record<string, Record<string, { colour: string; series: Array<[number, number]> }>> {
    const dataByPath = new Map<string, Map<string, { colour: string; series: Array<[number, number]> }>>()
    
    for (const [species, pathData] of Object.entries(timeseries)) {
        const geneId = metadata.species_gene_mapping[species]
        if (!geneId) continue
        
        const colour = metadata.gene_colours[geneId] ?? "gray"
        
        for (const [path, series] of Object.entries(pathData)) {
            if (!dataByPath.has(path)) {
                dataByPath.set(path, new Map())
            }
            dataByPath.get(path)!.set(geneId, { colour, series })
        }
    }
    
    // Convert to plain object
    const result: Record<string, Record<string, { colour: string; series: Array<[number, number]> }>> = {}

    dataByPath.forEach((geneMap, path) => {
        result[path] = {}
        geneMap.forEach((data, geneId) => {
            result[path][geneId] = data
        })
    })
    
    return result
}

/**
 * Track series data for SciChart visualization
 * Represents a single gene's data on a track (promoter/mrna/protein)
 */
// export interface TrackSeriesData {
//     geneId: string
//     colour: string
//     xData: number[]
//     yData: number[]
//     path: string  // Execution path ID (for branching simulations)
//     isDashed: boolean  // True for branch segments (front != back)
//     segmentFrom: number  // Start time of execution segment
//     segmentTo: number  // End time of execution segment
//     trackIndex: number  // Y-track index for this path (0 = first path, 1 = second path, etc.)
// }

/**
 * Calculate promoter activity fraction from active/inactive state timeseries
 * 
 * Merges active and inactive count events and computes fraction = active / (active + inactive)
 * at each timepoint. Matches the FractionSeries logic from inspect tool.
 * 
 * @param active Map of time → active count
 * @param inactive Map of time → inactive count
 * @returns Object with sorted time array and corresponding fraction array (0-1)
 */
// function calculatePromoterFraction(
//     active: Map<number, number>,
//     inactive: Map<number, number>
// ): { times: number[], fractions: number[] } {
//     const allTimes = new Set([...active.keys(), ...inactive.keys()])
//     const sortedTimes = Array.from(allTimes).sort((a, b) => a - b)
    
//     const fractions: number[] = []
//     let lastActive = 0
//     let lastInactive = 0
    
//     for (const t of sortedTimes) {
//         // Update state from events
//         if (active.has(t)) lastActive = active.get(t) || 0
//         if (inactive.has(t)) lastInactive = inactive.get(t) || 0
        
//         // Calculate fraction
//         const total = lastActive + lastInactive
//         const fraction = total === 0 ? 0.0 : lastActive / total
//         fractions.push(fraction)
//     }
    
//     return { times: sortedTimes, fractions }
// }

/**
 * Convert timeseries to track data for SciChart visualization
 * Keeps execution paths separate for proper branch rendering
 * 
 * Species naming convention (from GRS.jl):
 * - Promoter: "{geneId}.inactive" or "{geneId}.active"
 * - mRNA: "{geneId}.mrnas"
 * - Protein: "{geneId}.proteins"
 * 
 * @param timeseries Computed timeseries from simulation frames
 * @param geneColours Map of geneId → hex colour string
 * @param segments Optional timeline segments for segment boundary calculation
 * @returns Map of track kind → array of track series data (one per gene per path)
 */
// export function timeseriesToTrackData(
//     timeseries: TimeseriesData,
//     geneColours: Record<string, string>,
//     segments?: Array<{ path: string; from: number; to: number }>
// ): Record<'promoter' | 'mrna' | 'protein', TrackSeriesData[]> {
//     const tracks: Record<'promoter' | 'mrna' | 'protein', TrackSeriesData[]> = {
//         promoter: [],
//         mrna: [],
//         protein: []
//     }

//     // Build segment boundaries map: path → {from, to}
//     const segmentBoundaries = new Map<string, { from: number; to: number }>()
//     // Build path to track index map: path → track number (0, 1, 2, ...)
//     const pathToTrackIndex = new Map<string, number>()
//     if (segments) {
//         // First pass: extract unique paths in order and build maps
//         const seen = new Set<string>()
//         for (let i = 0; i < segments.length; i++) {
//             const segment = segments[i]
//             if (!segment) continue
//             segmentBoundaries.set(segment.path, { from: segment.from, to: segment.to })
//             if (!seen.has(segment.path)) {
//                 pathToTrackIndex.set(segment.path, pathToTrackIndex.size)
//                 seen.add(segment.path)
//             }
//         }
//     }

//     // Group by gene and path: geneId → path → kind → {active, inactive} | data
//     const genePathData: Record<string, Record<string, {
//         promoter?: { active: Array<[number, number]>, inactive: Array<[number, number]> },
//         mrna?: Array<[number, number]>,
//         protein?: Array<[number, number]>
//     }>> = {}

//     // Iterate through all species
//     for (const [speciesId, paths] of Object.entries(timeseries)) {
//         // Determine kind and geneId from speciesId
//         let kind: 'promoter' | 'mrna' | 'protein' | null = null
//         let geneId: string | null = null
//         let isActive: boolean | null = null

//         if (speciesId.includes('.inactive')) {
//             kind = 'promoter'
//             isActive = false
//             const parts = speciesId.split('.')
//             geneId = parts[0] || null
//         } else if (speciesId.includes('.active')) {
//             kind = 'promoter'
//             isActive = true
//             const parts = speciesId.split('.')
//             geneId = parts[0] || null
//         } else if (speciesId.includes('.mrnas')) {
//             kind = 'mrna'
//             const parts = speciesId.split('.')
//             geneId = parts[0] || null
//         } else if (speciesId.includes('.proteins')) {
//             kind = 'protein'
//             const parts = speciesId.split('.')
//             geneId = parts[0] || null
//         }

//         if (!kind || !geneId) continue

//         // Process each path separately (keep branches distinct)
//         for (const [pathId, pathData] of Object.entries(paths)) {
//             if (!Array.isArray(pathData)) continue

//             // Ensure data structures exist
//             if (!genePathData[geneId]) genePathData[geneId] = {}
//             const genePaths = genePathData[geneId]
//             if (!genePaths) continue
//             if (!genePaths[pathId]) genePaths[pathId] = {}

//             const pathEntry = genePaths[pathId]
//             if (!pathEntry) continue

//             if (kind === 'promoter') {
//                 if (!pathEntry.promoter) {
//                     pathEntry.promoter = { active: [], inactive: [] }
//                 }
//                 const targetArray = isActive ? pathEntry.promoter.active : pathEntry.promoter.inactive
//                 for (const [t, v] of pathData as Array<[number, number]>) {
//                     if (t !== undefined && v !== undefined && isFinite(t) && isFinite(v)) {
//                         targetArray.push([t, v])
//                     }
//                 }
//             } else {
//                 if (!pathEntry[kind]) {
//                     pathEntry[kind] = []
//                 }
//                 for (const [t, v] of pathData as Array<[number, number]>) {
//                     if (t !== undefined && v !== undefined && isFinite(t) && isFinite(v)) {
//                         pathEntry[kind]?.push([t, v])
//                     }
//                 }
//             }
//         }
//     }

//     // Convert to track series (one series per gene per path)
//     for (const [geneId, paths] of Object.entries(genePathData)) {
//         // Try both formats: 'gene_X' and plain 'X'
//         const colourKey = `gene_${geneId}`
//         let colour = geneColours[colourKey]
//         if (!colour) {
//             colour = geneColours[geneId]
//         }
//         const resolvedColour = colour || '#808080'

//         for (const [pathId, data] of Object.entries(paths)) {
//             // Determine if this is a branching path (heuristic: contains more than one segment)
//             // In practice, we'd check if front != back from segment metadata
//             const isDashed = pathId.includes(',') || pathId.length > 10

//             // Get segment boundaries and track index for this path
//             const segmentBounds = segmentBoundaries.get(pathId) || { from: 0, to: 0 }
//             const trackIndex = pathToTrackIndex.get(pathId) ?? 0

//             // Process mRNA
//             if (data.mrna && data.mrna.length > 0) {
//                 data.mrna.sort((a, b) => a[0] - b[0])
//                 const xData = data.mrna.map(p => p[0])
//                 const yData = data.mrna.map(p => p[1])
                
//                 // Extend to segment end by copying last value
//                 if (xData.length > 0 && segmentBounds.to > xData[xData.length - 1]) {
//                     xData.push(segmentBounds.to)
//                     yData.push(yData[yData.length - 1])
//                 }
                
//                 tracks.mrna.push({
//                     geneId,
//                     colour: resolvedColour,
//                     path: pathId,
//                     isDashed,
//                     segmentFrom: segmentBounds.from,
//                     segmentTo: segmentBounds.to,
//                     trackIndex,
//                     xData,
//                     yData
//                 })
//             }

//             // Process protein
//             if (data.protein && data.protein.length > 0) {
//                 data.protein.sort((a, b) => a[0] - b[0])
//                 const xData = data.protein.map(p => p[0])
//                 const yData = data.protein.map(p => p[1])
                
//                 // Extend to segment end by copying last value
//                 if (xData.length > 0 && segmentBounds.to > xData[xData.length - 1]) {
//                     xData.push(segmentBounds.to)
//                     yData.push(yData[yData.length - 1])
//                 }
                
//                 tracks.protein.push({
//                     geneId,
//                     colour: resolvedColour,
//                     path: pathId,
//                     isDashed,
//                     segmentFrom: segmentBounds.from,
//                     segmentTo: segmentBounds.to,
//                     trackIndex,
//                     xData,
//                     yData
//                 })
//             }

//             // Process promoter (calculate fractions)
//             if (data.promoter) {
//                 const { active, inactive } = data.promoter
//                 if (active.length > 0 || inactive.length > 0) {
//                     active.sort((a, b) => a[0] - b[0])
//                     inactive.sort((a, b) => a[0] - b[0])

//                     const activeMap = new Map(active)
//                     const inactiveMap = new Map(inactive)
//                     const fracResult = calculatePromoterFraction(activeMap, inactiveMap)
//                     const times = [...fracResult.times]
//                     const fractions = [...fracResult.fractions]

//                     // Extend to segment end by copying last value
//                     if (times.length > 0 && segmentBounds.to > times[times.length - 1]) {
//                         times.push(segmentBounds.to)
//                         fractions.push(fractions[fractions.length - 1])
//                     }

//                     tracks.promoter.push({
//                         geneId,
//                         colour: resolvedColour,
//                         path: pathId,
//                         isDashed,
//                         segmentFrom: segmentBounds.from,
//                         segmentTo: segmentBounds.to,
//                         trackIndex,
//                         xData: times,
//                         yData: fractions
//                     })
//                 }
//             }
//         }
//     }

//     return tracks
// }

/**
 * Format result label for display in dropdown
 * Works with both metadata and fully loaded results
 * Prefers created_at from API response, falls back to parsing id as ISO 8601 timestamp
 */
export function formatResultLabel(result: SimulationResultMetadata | SimulationResult | undefined | null): string {
    if (!result) return ''
    
    let date: Date
    if (result.created_at) {
        date = new Date(result.created_at)
    } else {
        // Fallback: parse id as ISO 8601 timestamp
        date = new Date(result.id)
    }
    
    const dateStr = date.toLocaleString()
    return `${result.schedule_name || 'Unknown'} – ${dateStr}`
}



