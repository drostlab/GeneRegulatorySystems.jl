export const SPECIES_TYPES = ['active', 'elongations', 'premrnas', 'mrnas', 'proteins'] as const
export type SpeciesType = typeof SPECIES_TYPES[number]

export const DEFAULT_VISIBLE_SPECIES_TYPES: SpeciesType[] = ['active', 'mrnas', 'proteins']

export const speciesTypeLabels: Record<SpeciesType, string> = {
    'active': 'Promoter activity',
    'elongations': 'Elongation counts',
    'premrnas': 'Pre-mRNA counts',
    'mrnas': 'mRNA counts',
    'proteins': 'Protein counts'
}

export interface TimelineSegment {
    id: number
    execution_path: string
    model_path: string
    from: number
    to: number
    label: string
}

export interface StructureNode {
    type: 'scope' | 'sequence' | 'branch' | 'leaf'
    execution_path: string
    label: string
    children: StructureNode[]
}

export interface ScheduleData {
    segments: TimelineSegment[]
    structure: StructureNode
    genes: string[]
    gene_colours: Record<string, string>
}

export const VALID_SCHEDULE_SOURCES = ['examples', 'user', 'snapshot'] as const
export type ScheduleSource = typeof VALID_SCHEDULE_SOURCES[number]

export interface ReifiedSchedule {
    name: string
    source: ScheduleSource
    spec: string
    data: ScheduleData | null
    validationMessages?: Array<{ type: 'error' | 'warning' | 'info'; content: string }>
}

export type Schedule = ReifiedSchedule

// ============================================================================
// Utility functions
// ============================================================================

/**
 * Extract gene name from a species name (e.g. "geneA.proteins" -> "geneA").
 * Returns null if the species suffix is not a known SPECIES_TYPE.
 */
export function getGeneFromSpeciesName(species: string): string | null {
    for (const t of SPECIES_TYPES) {
        if (species.endsWith(`.${t}`)) {
            return species.slice(0, -(t.length + 1))
        }
    }
    return null
}

export function extractAllGeneIds(data: ScheduleData): string[] {
    return [...data.genes].sort()
}

export function getSpeciesForGene(_data: ScheduleData, gene: string): string[] {
    return SPECIES_TYPES.map(t => `${gene}.${t}`)
}

export function getSpeciesForType(data: ScheduleData, speciesType: SpeciesType): string[] {
    return data.genes.map(g => `${g}.${speciesType}`)
}

export function computeScheduleKey(schedule: ReifiedSchedule): string
export function computeScheduleKey(name: string, source: ScheduleSource): string
export function computeScheduleKey(scheduleOrName: ReifiedSchedule | string, source?: ScheduleSource): string {
    if (typeof scheduleOrName === 'string') {
        return `${source}/${scheduleOrName}`
    }
    return `${scheduleOrName.source}/${scheduleOrName.name}`
}

export function parseScheduleKey(key: string): { source: ScheduleSource; name: string } {
    const [source, ...nameParts] = key.split('/')
    if (!VALID_SCHEDULE_SOURCES.includes(source as ScheduleSource)) {
        throw new Error(`Invalid schedule source: ${source}`)
    }
    return { source: source as ScheduleSource, name: nameParts.join('/') }
}

export function extractPaths(segments: TimelineSegment[]): string[] {
    const paths: string[] = []
    const seen = new Set<string>()
    for (const segment of segments) {
        if (!seen.has(segment.execution_path)) {
            paths.push(segment.execution_path)
            seen.add(segment.execution_path)
        }
    }
    return paths
}

export function getTimeExtent(segments: TimelineSegment[]): { min: number; max: number } {
    if (segments.length === 0) return { min: 0, max: 0 }
    let min = segments[0]!.from
    let max = segments[0]!.to
    for (const segment of segments) {
        min = Math.min(min, segment.from)
        max = Math.max(max, segment.to)
    }
    return { min, max }
}

/**
 * Derive paths from selected segment IDs.
 */
export function getPathsForSegmentIds(segments: TimelineSegment[], ids: Set<number>): Set<string> {
    const paths = new Set<string>()
    for (const seg of segments) {
        if (ids.has(seg.id)) {
            paths.add(seg.execution_path)
        }
    }
    return paths
}

/**
 * Get unique model_paths from segments (skipping instant segments).
 */
export function getUniqueModelPaths(segments: TimelineSegment[]): string[] {
    const paths = new Set<string>()
    for (const seg of segments) {
        if (seg.from !== seg.to) {
            paths.add(seg.model_path)
        }
    }
    return Array.from(paths)
}

/**
 * Find the model_path of the segment containing a given timepoint.
 * Skips instant segments (from === to). Returns first model_path if none match.
 */
export function getModelPathAtTime(segments: TimelineSegment[], t: number): string | null {
    let fallback: string | null = null
    for (const seg of segments) {
        if (seg.from === seg.to) continue
        if (fallback === null) fallback = seg.model_path
        if (t >= seg.from && t <= seg.to) return seg.model_path
    }
    return fallback
}
