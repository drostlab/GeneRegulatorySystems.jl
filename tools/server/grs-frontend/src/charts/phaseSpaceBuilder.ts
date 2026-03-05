/**
 * Builds a PhaseSpaceResult client-side from the timeseries cache
 * for small gene selections (1-2 genes), avoiding a server round-trip.
 *
 * - 1 gene: X = mRNA counts, Y = protein counts
 * - 2 genes: X = gene1 protein, Y = gene2 protein
 */
import type { TimeseriesData, PhaseSpaceResult, PhaseSpacePoint } from '@/types/simulation'

/**
 * Build a 2D phase-space result from cached timeseries data.
 *
 * @param timeseries - Full timeseries cache (species -> path -> [[t, v], ...])
 * @param genes - 1 or 2 selected gene IDs
 * @param geneColours - Mapping from gene ID to hex colour
 * @param simulationId - Current simulation ID (for metadata)
 * @returns PhaseSpaceResult ready to pass to PhaseSpacePanel, or null if data is insufficient
 */
export function buildClientPhaseSpace(
    timeseries: TimeseriesData,
    genes: string[],
    geneColours: Record<string, string>,
    simulationId: string
): PhaseSpaceResult | null {
    if (genes.length === 1) {
        return buildSingleGenePhaseSpace(timeseries, genes[0]!, geneColours, simulationId)
    }
    if (genes.length === 2) {
        return buildTwoGenePhaseSpace(timeseries, genes[0]!, genes[1]!, geneColours, simulationId)
    }
    return null
}

/** 1 gene: X = mRNA, Y = protein. Each path becomes a trajectory. */
function buildSingleGenePhaseSpace(
    timeseries: TimeseriesData,
    gene: string,
    geneColours: Record<string, string>,
    simulationId: string
): PhaseSpaceResult | null {
    const mrnaKey = `${gene}.mrnas`
    const proteinKey = `${gene}.proteins`
    const mrnaByPath = timeseries[mrnaKey]
    const proteinByPath = timeseries[proteinKey]
    if (!mrnaByPath || !proteinByPath) return null

    const colour = geneColours[gene] ?? '#888888'
    const points = pairTimeseriesByPath(mrnaByPath, proteinByPath, colour)
    if (points.length === 0) return null

    return {
        simulation_id: simulationId,
        method: 'client-2d',
        axis_labels: [`${gene} mRNA`, `${gene} protein`],
        axis_top_genes: [gene],
        points,
        n_genes: 1,
        n_cells: points.length,
    }
}

/** 2 genes: X = gene1 protein, Y = gene2 protein. */
function buildTwoGenePhaseSpace(
    timeseries: TimeseriesData,
    gene1: string,
    gene2: string,
    geneColours: Record<string, string>,
    simulationId: string
): PhaseSpaceResult | null {
    const protein1ByPath = timeseries[`${gene1}.proteins`]
    const protein2ByPath = timeseries[`${gene2}.proteins`]
    if (!protein1ByPath || !protein2ByPath) return null

    const colour = geneColours[gene1] ?? '#888888'
    const points = pairTimeseriesByPath(protein1ByPath, protein2ByPath, colour)
    if (points.length === 0) return null

    return {
        simulation_id: simulationId,
        method: 'client-2d',
        axis_labels: [`${gene1} protein`, `${gene2} protein`],
        axis_top_genes: [gene1, gene2],
        points,
        n_genes: 2,
        n_cells: points.length,
    }
}

/**
 * Pair two species' timeseries by matching timepoints within each path.
 * Both maps are path -> Array<[time, value]>. Only timepoints present in both are kept.
 */
function pairTimeseriesByPath(
    xByPath: Record<string, Array<[number, number]>>,
    yByPath: Record<string, Array<[number, number]>>,
    colour: string
): PhaseSpacePoint[] {
    const points: PhaseSpacePoint[] = []

    for (const path of Object.keys(xByPath)) {
        const xSeries = xByPath[path]
        const ySeries = yByPath[path]
        if (!xSeries || !ySeries) continue

        const yByTime = new Map<number, number>()
        for (const [t, v] of ySeries) {
            yByTime.set(t, v)
        }

        for (const [t, xVal] of xSeries) {
            const yVal = yByTime.get(t)
            if (yVal === undefined) continue
            points.push({ x: xVal, y: yVal, path, t, colour })
        }
    }

    return points
}
