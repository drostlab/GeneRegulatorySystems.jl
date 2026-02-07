import type { Network } from './network'

/**
 * Species types in the regulatory network
 */
export const SPECIES_TYPES = ['active', 'elongations', 'premrnas', 'rnas', 'proteins'] as const
export type SpeciesType = typeof SPECIES_TYPES[number]

/**
 * Default species types to display
 */
export const DEFAULT_VISIBLE_SPECIES_TYPES: SpeciesType[] = ['active', 'rnas', 'proteins']

/**
 * Display labels for species types
 */
export const speciesTypeLabels: Record<SpeciesType, string> = {
    'active': 'Promoter activity',
    'elongations': 'Elongation counts',
    'premrnas': 'Pre-mRNA counts',
    'rnas': 'RNA counts',
    'proteins': 'Protein counts'
}

/**
 * Schedule represents a specification loaded for visualization and editing.
 * It contains the specification in two forms:
 * - data: ScheduleData (reified specification structure for visualization)
 * - spec: string (original DSL source)
 * 
 * Also includes validation messages from parsing/analysis.
 * 
 * Note: This is NOT a runtime schedule object. It lacks execution state.
 * Runtime execution is handled by the Julia backend.
 */

/**
 * Timeline segment - a continuous execution path with duration
 */
export interface TimelineSegment {
    path: string
    from: number
    to: number
    label: string
}

export interface ScheduleVisMetadata {
    gene_colours: Record<string, string>
}

/**
 * Complete visualization schema from backend
 */
export interface ScheduleData {
    network: Network
    segments: TimelineSegment[]
    vis_metadata: ScheduleVisMetadata
    species_gene_mapping: Record<string, string>
}

/**
 * Extract all unique gene IDs from schedule data
 * @param data - Schedule data with shared network
 * @returns Sorted array of unique gene IDs
 */
export function extractAllGeneIds(data: ScheduleData): string[] {
    const allGenes = new Set<string>()
    
    if (data.network?.nodes) {
        for (const node of data.network.nodes) {
            if (node.kind === 'gene') {
                allGenes.add(node.name)
            }
        }
    }
    
    return Array.from(allGenes).sort()
}



export const VALID_SCHEDULE_SOURCES = ['examples', 'user', 'snapshot'] as const;
export type ScheduleSource = typeof VALID_SCHEDULE_SOURCES[number];

/**
 * ReifiedSchedule - loaded schedule data with metadata
 * 
 * Represents either:
 * - Example schedule: source='examples', loaded from storage/schedules/examples/
 * - User schedule: source='user', loaded from storage/schedules/user/
 * - Snapshot: source='snapshot', transient in-memory snapshot of a simulation result
 */
export interface ReifiedSchedule {
    name: string
    source: ScheduleSource 
    spec: string
    data: ScheduleData | null
    validationMessages?: Array<{ type: 'error' | 'warning' | 'info'; content: string }>
}

/**
 * Alias for backwards compatibility
 */
export type Schedule = ReifiedSchedule

// Overload signatures
export function computeScheduleKey(schedule: ReifiedSchedule): string
export function computeScheduleKey(name: string, source: ScheduleSource): string

// Implementation
export function computeScheduleKey(scheduleOrName: ReifiedSchedule | string, source?: ScheduleSource): string {
    if (typeof scheduleOrName === 'string') {
        return `${source}/${scheduleOrName}`
    }
    return `${scheduleOrName.source}/${scheduleOrName.name}`
}

export function parseScheduleKey(key: string): {source: ScheduleSource, name: string} {
    const [source, ...nameParts] = key.split('/')
    if (!VALID_SCHEDULE_SOURCES.includes(source as ScheduleSource)) {
        throw new Error(`Invalid schedule source: ${source}`)
    }
    const result = { source: source as ScheduleSource, name: nameParts.join('/') }
    return result
}

/**
 * Extract all unique execution paths from schedule segments in order of appearance
 */
export function extractPaths(segments: TimelineSegment[]): string[] {
    const paths: string[] = []
    const seen = new Set<string>()
    for (const segment of segments) {
        if (!seen.has(segment.path)) {
            paths.push(segment.path)
            seen.add(segment.path)
        }
    }
    return paths
}

/**
 * Group segments by their path prefix (before the final index)
 * Segments with the same prefix (e.g., all "++/1", "++/3", "++/4") share a track
 * The prefix determines grouping: "-" means sequential, "/" means branched
 */
function buildTemporalChains(segments: TimelineSegment[]): Map<string, number> {
    const pathToTrack = new Map<string, number>()
    const prefixToTrack = new Map<string, number>()
    let nextTrackIndex = 0

    // Sort by first appearance
    const seen = new Set<string>()
    const ordered = segments.filter(s => {
        if (seen.has(s.path)) return false
        seen.add(s.path)
        return true
    })

    for (const segment of ordered) {
        // Extract prefix by removing trailing digits/separators
        // E.g., "++/1" → "++/", "++/3" → "++/", "++-1" → "++-"
        const prefix = segment.path.replace(/(-|\/)\d+$/, '$1')

        if (!prefixToTrack.has(prefix)) {
            prefixToTrack.set(prefix, nextTrackIndex++)
        }

        const trackIndex = prefixToTrack.get(prefix)!
        pathToTrack.set(segment.path, trackIndex)
    }

    return pathToTrack
}

/**
 * Build mapping of execution path to track index (y-position)
 * Each unique path gets a track number based on order of first appearance in segments
 * Used for positioning bands vertically - each execution path gets its own row
 * @param segments Timeline segments from schedule
 * @returns Map of path ID → track index (0, 1, 2, ...)
 */
export function buildPathToTrackMap(segments: TimelineSegment[]): Map<string, number> {
    return buildTemporalChains(segments)
}

/**
 * Check if a path is valid according to the schedule
 */
export function isValidPath(paths: string[], path: string): boolean {
    return paths.includes(path)
}

/**
 * Timeline segment for visualization on schedule track
 * Represents a single segment's display properties for rendering
 */
export interface ScheduleSegmentDisplay {
    path: string
    from: number
    to: number
    label: string
    isInstant: boolean  // from === to
    colour: string
    trackIndex: number  // Y-position (0 = first path, 1 = second path, etc.)
}

/**
 * Get the first available path from segments
 */
export function getFirstPath(segments: TimelineSegment[]): string | null {
    const paths = extractPaths(segments)
    return paths[0] ?? null
}

/**
 * Convert schedule segments to display data for timeline visualization
 * Creates one display entry per segment with colour based on type (instant vs non-instant)
 * 
 * @param segments Timeline segments from schedule
 * @returns Array of ScheduleSegmentDisplay for timeline rendering
 */
export function convertSegmentsToDisplayData(segments: TimelineSegment[]): ScheduleSegmentDisplay[] {
    const pathToTrack = buildPathToTrackMap(segments)

    return segments.map(segment => {
        const isInstant = segment.from === segment.to
        const trackIndex = pathToTrack.get(segment.path) ?? 0
        const colour = isInstant ? '#e45649' : '#50a14f'  // Red for instant, green for non-instant

        return {
            path: segment.path,
            from: segment.from,
            to: segment.to,
            label: segment.label,
            isInstant,
            colour,
            trackIndex
        }
    })
}

