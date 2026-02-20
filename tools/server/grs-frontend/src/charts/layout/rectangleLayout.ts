import type { StructureNode, TimelineSegment } from '@/types/schedule'

export interface LayoutRectangle {
    segmentId: number
    executionPath: string
    modelPath: string
    label: string
    x1: number
    x2: number
    y1: number
    y2: number
    isInstant: boolean
}

export function layoutRectangles(
    structure: StructureNode,
    segments: TimelineSegment[],
    yMin: number,
    yMax: number
): LayoutRectangle[] {
    const segmentsByPath = groupSegmentsByPath(segments)
    const rectangles: LayoutRectangle[] = []
    layoutNode(structure, segmentsByPath, yMin, yMax, rectangles)
    console.debug(`[rectangleLayout] ${segments.length} segments -> ${rectangles.length} rectangles`)
    for (const r of rectangles) {
        console.debug(`[rectangleLayout]  id=${r.segmentId} path=${r.executionPath} x=[${r.x1},${r.x2}] y=[${r.y1.toFixed(3)},${r.y2.toFixed(3)}]`)
    }
    return rectangles
}

function groupSegmentsByPath(segments: TimelineSegment[]): Map<string, TimelineSegment[]> {
    const map = new Map<string, TimelineSegment[]>()
    for (const seg of segments) {
        const list = map.get(seg.execution_path)
        if (list) {
            list.push(seg)
        } else {
            map.set(seg.execution_path, [seg])
        }
    }
    return map
}

/**
 * Returns true if this node or any descendant is a branch node.
 * A sequence whose children contain branches effectively runs in parallel
 * (the Branched state gets unwrapped to the stem on each outer iteration),
 * so it must be laid out like a branch.
 */
function subtreeHasBranch(node: StructureNode): boolean {
    if (node.type === 'branch') return true
    return node.children.some(subtreeHasBranch)
}

function layoutNode(
    node: StructureNode,
    segmentsByPath: Map<string, TimelineSegment[]>,
    yMin: number,
    yMax: number,
    out: LayoutRectangle[]
): void {
    if (node.type === 'leaf') {
        layoutLeaf(node, segmentsByPath, yMin, yMax, out)
        return
    }

    if (node.children.length === 0) return

    if (node.type === 'branch' || (node.type === 'sequence' && node.children.some(subtreeHasBranch))) {
        layoutBranched(node, segmentsByPath, yMin, yMax, out)
    } else {
        // scope, sequence (no branch descendants): children share the full y-range
        for (const child of node.children) {
            layoutNode(child, segmentsByPath, yMin, yMax, out)
        }
    }
}

function layoutLeaf(
    node: StructureNode,
    segmentsByPath: Map<string, TimelineSegment[]>,
    yMin: number,
    yMax: number,
    out: LayoutRectangle[]
): void {
    const segs = segmentsByPath.get(node.execution_path) ?? []
    for (const seg of segs) {
        out.push({
            segmentId: seg.id,
            executionPath: seg.execution_path,
            modelPath: seg.model_path,
            label: seg.label,
            x1: seg.from,
            x2: seg.to,
            y1: yMin,
            y2: yMax,
            isInstant: seg.from === seg.to
        })
    }
}

function layoutBranched(
    node: StructureNode,
    segmentsByPath: Map<string, TimelineSegment[]>,
    yMin: number,
    yMax: number,
    out: LayoutRectangle[]
): void {
    const n = node.children.length
    if (n === 0) return
    const bandHeight = (yMax - yMin) / n
    // Assign top-to-bottom: first child gets highest y-band
    for (let i = 0; i < n; i++) {
        const childYMax = yMax - i * bandHeight
        const childYMin = childYMax - bandHeight
        layoutNode(node.children[i]!, segmentsByPath, childYMin, childYMax, out)
    }
}

/**
 * Walk the structure tree with the same y-band splitting logic as layoutRectangles
 * to produce yRanges for ALL leaf paths, not just those with segments.
 */
export function collectPathYRanges(
    structure: StructureNode,
    yMin: number = 0,
    yMax: number = 1
): Map<string, { yMin: number; yMax: number }> {
    const ranges = new Map<string, { yMin: number; yMax: number }>()
    collectNodeRanges(structure, yMin, yMax, ranges)
    return ranges
}

function collectNodeRanges(
    node: StructureNode,
    yMin: number,
    yMax: number,
    out: Map<string, { yMin: number; yMax: number }>
): void {
    if (node.type === 'leaf') {
        const existing = out.get(node.execution_path)
        if (existing) {
            existing.yMin = Math.min(existing.yMin, yMin)
            existing.yMax = Math.max(existing.yMax, yMax)
        } else {
            out.set(node.execution_path, { yMin, yMax })
        }
        return
    }
    if (node.children.length === 0) return

    if (node.type === 'branch' || (node.type === 'sequence' && node.children.some(subtreeHasBranch))) {
        const n = node.children.length
        const bandHeight = (yMax - yMin) / n
        // Top-to-bottom: first child gets highest y-band
        for (let i = 0; i < n; i++) {
            const childYMax = yMax - i * bandHeight
            const childYMin = childYMax - bandHeight
            collectNodeRanges(node.children[i]!, childYMin, childYMax, out)
        }
    } else {
        // scope, sequence (no branch descendants): children share full y-range
        for (const child of node.children) {
            collectNodeRanges(child, yMin, yMax, out)
        }
    }
}
