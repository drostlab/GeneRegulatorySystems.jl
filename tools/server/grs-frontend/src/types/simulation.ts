export type TimeseriesData = Record<string, Record<string, Array<[number, number]>>>

export interface TimeseriesMetadata {
    species_gene_mapping: Record<string, string>
    gene_colours: Record<string, string>
    time_extent: { min: number; max: number }
}

export type SimulationStatus = 'running' | 'completed' | 'error'

export interface SimulationData {
    timeseries: TimeseriesData
}

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

export interface SimulationResult extends Omit<SimulationResultMetadata, 'data'> {
    data: SimulationData
}

export function isResultLoaded(result: SimulationResultMetadata | SimulationResult): result is SimulationResult {
    return result.data !== null
}

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

export function restructureTimeseriesByPathAndGene(
    timeseries: TimeseriesData,
    metadata: TimeseriesMetadata
): Record<string, Record<string, { colour: string; series: Array<[number, number]> }>> {
    const dataByPath = new Map<string, Map<string, { colour: string; series: Array<[number, number]> }>>()

    for (const [species, pathData] of Object.entries(timeseries)) {
        const geneId = metadata.species_gene_mapping[species]
        if (!geneId) continue

        const colour = metadata.gene_colours[geneId] ?? 'gray'

        for (const [path, series] of Object.entries(pathData)) {
            if (!dataByPath.has(path)) {
                dataByPath.set(path, new Map())
            }
            dataByPath.get(path)!.set(geneId, { colour, series })
        }
    }

    const result: Record<string, Record<string, { colour: string; series: Array<[number, number]> }>> = {}
    dataByPath.forEach((geneMap, path) => {
        result[path] = {}
        geneMap.forEach((data, geneId) => {
            result[path]![geneId] = data
        })
    })

    return result
}

export function formatResultLabel(result: SimulationResultMetadata | SimulationResult | undefined | null): string {
    if (!result) return ''

    let date: Date
    if (result.created_at) {
        date = new Date(result.created_at)
    } else {
        date = new Date(result.id)
    }

    return `${result.schedule_name || 'Unknown'} - ${date.toLocaleString()}`
}
