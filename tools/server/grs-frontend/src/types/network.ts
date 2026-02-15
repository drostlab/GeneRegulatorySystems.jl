/**
 * Network types matching Julia backend NetworkRepresentation module
 */

export interface Node {
    kind: string
    name: string
    parent: string | null
    properties: Record<string, any>
}

export interface Link {
    kind: string
    from: string
    to: string
    properties: Record<string, any>
}

export interface Network {
    nodes: Node[]
    links: Link[]
}

/** Nodes and links absent from a specific model (relative to the union). */
export interface ModelExclusions {
    nodes: string[]
    links: string[]
}

/** Union of all model networks with per-model exclusion lists. */
export interface UnionNetwork {
    nodes: Node[]
    links: Link[]
    model_exclusions: Record<string, ModelExclusions>
}

/** Generate a stable edge ID matching the backend convention. */
export function linkId(link: Link): string {
    return `${link.from}-${link.kind}-${link.to}`
}

/** Node kinds that represent container/model-level nodes (filtered out of visualisation). */
export const MODEL_NODE_KINDS = new Set([
    'v1_model', 'reaction_system', 'differentiation_model',
    'differentiation_core', 'kronecker_network', 'instant'
])

