/**
 * Node in a network - Cytoscape compatible
 */
export interface Node {
    id: string
    label: string
    parent: string | null
    kind: string
    properties: Record<string, any>
}

/**
 * Edge in a network - Cytoscape compatible
 */
export interface Edge {
    source: string
    target: string
    kind: string
    properties: Record<string, any>
}

/**
 * Flat network representation
 */
export interface Network {
    nodes: Node[]
    edges: Edge[]
}

    const elements: any[] = []
