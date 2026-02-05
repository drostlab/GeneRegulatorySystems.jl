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

    const elements: any[] = []
