import type { Network } from './network'

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
    bindings?: Record<string, unknown>
}

export interface ScheduleVisMetadata {
    geneColours: Record<string, string>
}

/**
 * Complete visualization schema from backend
 */
export interface ScheduleData {
    network: Network
    segments: TimelineSegment[]
    visMetadata: ScheduleVisMetadata 
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
                allGenes.add(node.id)
            }
        }
    }
    
    return Array.from(allGenes).sort()
}

/**
 * Colour palette for genes (20+ distinct colours)
 */
export const GENE_COLOUR_PALETTE: string[] = [
    '#E41A1C', '#FF7F00', '#4DAF4A', '#984EA3', '#377EB8',
    '#A65628', '#F781BF', '#999999', '#66C2A5', '#FC8D62',
    '#8DA0CB', '#E78AC3', '#A6D854', '#FFD92F', '#E5C494',
    '#B3B3B3', '#FB8072', '#80B1D3', '#FDB462', '#B3DE69'
]

/**
 * Generate default visualization metadata from schedule data
 * Extracts all unique genes from segments and assigns colours deterministically
 * @param data - Schedule data with segments
 * @returns Default visualization metadata with gene colours
 */
export function generateDefaultVisMetadata(data: ScheduleData): ScheduleVisMetadata {
    const geneList = extractAllGeneIds(data)
    const geneColours: Record<string, string> = {}
    
    // assign gene colours
    for (let i = 0; i < geneList.length; i++) {
        const colour = GENE_COLOUR_PALETTE[i % GENE_COLOUR_PALETTE.length]
        geneColours[geneList[i]!] = colour ?? '#999999'
    }
    
    return { geneColours }
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
 * Build mapping of execution path to track index (y-position)
 * Each unique path gets a track number based on order of first appearance in segments
 * Used for positioning bands vertically - each execution path gets its own row
 * @param segments Timeline segments from schedule
 * @returns Map of path ID → track index (0, 1, 2, ...)
 */
export function buildPathToTrackMap(segments: TimelineSegment[]): Map<string, number> {
    const pathToTrack = new Map<string, number>()
    const paths = extractPaths(segments)
    for (let i = 0; i < paths.length; i++) {
        pathToTrack.set(paths[i], i)
    }
    return pathToTrack
}

/**
 * Check if a path is valid according to the schedule
 */
export function isValidPath(paths: string[], path: string): boolean {
    return paths.includes(path)
}

/**
 * Get the first available path from segments
 */
export function getFirstPath(segments: TimelineSegment[]): string | null {
    const paths = extractPaths(segments)
    return paths[0] ?? null
}

