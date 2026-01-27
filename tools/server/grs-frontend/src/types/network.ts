/**
 * Base type for all entities in a network
 */
export interface Entity {
    uid: string
    stateId: string | null
    type: 'species' | 'reaction' | 'gene' | 'differentiator'
    parent: string | null
    label: string
}

/**
 * Molecular species (gene product or intermediate)
 */
export interface SpeciesEntity extends Entity {
    type: 'species'
}

/**
 * Mass action reaction with typed inputs and outputs
 */
export interface ReactionEntity extends Entity {
    type: 'reaction'
    inputs: Array<{ stateId: string; stoichiometry: number }>
    outputs: Array<{ stateId: string; stoichiometry: number }>
    rate_forward: number
    rate_reverse: number | null
}

/**
 * Gene with regulatory network and typed regulation edges
 */
export interface GeneEntity extends Entity {
    type: 'gene'
    label: string
    baseRates: Record<string, number>
    activation: Array<{ fromGeneId: string; at: number; k: number }>
    repression: Array<{ fromGeneId: string; at: number; k: number }>
    proteolysis: Array<{ fromGeneId: string; k: number }>
    promoterInactiveId: string
    promoterActiveId: string
    proteinStateId: string
    mrnaStateId: string
}

/**
 * Edge type in network
 */
export interface Edge {
    source: string
    target: string
    type: 'input' | 'output' | 'activation' | 'repression' | 'proteolysis'
    affinity?: number
    hill?: number
}

/**
 * Network of entities with edges
 */
export interface Network {
    id: string
    entities: Entity[]
    edges: Edge[]
}

/**
 * Convert network to Cytoscape format
 * Builds compound nodes where genes are parent containers for their reactions/species
 * @param network - The network to convert
 * @param geneColours - Map of gene UIDs to hex colour strings
 * @returns Array of Cytoscape elements (nodes and edges)
 */
export function networkToCytoscapeData(network: Network, geneColours: Record<string, string> = {}): any[] {
    const elements: any[] = []
    
    // Build a map of numeric IDs to gene UIDs
    const numericIdToGeneId: Record<string, string> = {}
    for (const entity of network.entities) {
        if (entity.type === 'gene') {
            const geneNum = entity.uid.replace('gene_', '')
            numericIdToGeneId[geneNum] = entity.uid
        }
    }
    
    // Track numeric ID nodes that are aliases for genes (should be skipped)
    const numericIdNodeUIDs = new Set(Object.keys(numericIdToGeneId))
    
    const getParentGene = (entity: Entity): string | undefined => {
        if (entity.type === 'gene') return undefined
        if (entity.parent) return entity.parent
        
        if (entity.type === 'species') {
            // Check if this is a state of a gene by checking gene properties
            for (const e of network.entities) {
                if (e.type === 'gene') {
                    const gene = e as any
                    if (gene.mrnaStateId === entity.uid || 
                        gene.proteinStateId === entity.uid ||
                        gene.promoterActiveId === entity.uid ||
                        gene.promoterInactiveId === entity.uid) {
                        return gene.uid
                    }
                }
            }
            
            // Check if it's a numeric ID that maps to a gene (skip these, they're aliases)
            if (numericIdNodeUIDs.has(entity.uid)) {
                return undefined
            }
            
            // Check if it's a promoter node like "1_promoter_active", "1_promoter_inactive"
            const promoterMatch = entity.uid.match(/^(\d+)_promoter/)
            if (promoterMatch) {
                return numericIdToGeneId[promoterMatch[1]!]
            }
            
            // Check if it's like "1_mrna", "1_protein", etc
            const match = entity.uid.match(/^(\d+)_/)
            if (match) {
                return numericIdToGeneId[match[1]!]
            }
        }
        
        if (entity.type === 'reaction') {
            const reaction = entity as any
            if (reaction.geneId) return reaction.geneId
            
            // Check if it's like "1_transcription", "1_translation", etc
            const match = entity.uid.match(/^(\d+)_/)
            if (match) {
                return numericIdToGeneId[match[1]!]
            }
        }
        
        return undefined
    }
    
    // Add nodes from entities (skip numeric ID aliases)
    for (const entity of network.entities) {
        // Skip numeric ID nodes - they're aliases for genes
        if (numericIdNodeUIDs.has(entity.uid)) {
            continue
        }
        
        const parentGeneId = getParentGene(entity)
        let colour: string
        
        if (entity.type === 'gene') {
            const baseColour = geneColours[entity.uid] || '#999999'
            colour = desaturateAndLighten(baseColour)
        } else {
            colour = geneColours[parentGeneId!] || '#999999'
        }
        
        elements.push({
            data: {
                id: entity.uid,
                label: entity.label || entity.uid,
                type: entity.type,
                parent: parentGeneId,
                colour: colour
            },
            classes: entity.type
        })
    }
    
    // Create placeholder nodes for missing edge endpoints
    const nodeIds = new Set(network.entities.map(e => e.uid).filter(id => !numericIdNodeUIDs.has(id)))
    const edgeNodeIds = new Set<string>()
    
    for (const edge of network.edges) {
        edgeNodeIds.add(edge.source)
        edgeNodeIds.add(edge.target)
    }
    
    for (const nodeId of edgeNodeIds) {
        if (!nodeIds.has(nodeId)) {
            let type = 'species'
            let parentGeneId: string | undefined
            
            // Skip numeric IDs - map them to their gene instead
            if (numericIdNodeUIDs.has(nodeId)) {
                continue
            }
            
            if (nodeId.includes('_transcription') || nodeId.includes('_translation') || nodeId.includes('_decay')) {
                type = 'reaction'
            }
            
            // Check for promoter node pattern first
            const promoterMatch = nodeId.match(/^(\d+)_promoter/)
            if (promoterMatch) {
                parentGeneId = numericIdToGeneId[promoterMatch[1]!]
            } else {
                // Infer parent from ID pattern
                const match = nodeId.match(/^(\d+)_/)
                if (match) {
                    parentGeneId = numericIdToGeneId[match[1]!]
                }
            }
            
            const colour = parentGeneId ? (geneColours[parentGeneId] || '#999999') : '#999999'
            
            elements.push({
                data: {
                    id: nodeId,
                    label: nodeId,
                    type,
                    parent: parentGeneId,
                    colour: colour
                },
                classes: type
            })
            
            nodeIds.add(nodeId)
        }
    }
    
    // Add edges
    for (const edge of network.edges) {
        let edgeColour = '#999999'
        
        if (edge.type === 'activation') {
            edgeColour = '#787878'
        } else if (edge.type === 'repression') {
            edgeColour = '#e16868'
        } else if (edge.type === 'proteolysis') {
            edgeColour = '#FF7F00'
        } else if (edge.type === 'input') {
            edgeColour = '#999999'
        } else if (edge.type === 'output') {
            edgeColour = '#666666'
        }
        
        // Map numeric IDs to their gene nodes
        let source = edge.source
        let target = edge.target
        
        if (numericIdNodeUIDs.has(source)) {
            source = numericIdToGeneId[source] || source
        }
        if (numericIdNodeUIDs.has(target)) {
            target = numericIdToGeneId[target] || target
        }
        
        // Build label for regulation edges
        let edgeLabel = ''
        if ((edge.type === 'activation' || edge.type === 'repression' || edge.type === 'proteolysis') && edge.affinity !== undefined) {
            edgeLabel = `K=${edge.affinity.toFixed(2)}`
        }
        
        elements.push({
            data: {
                id: `${source}-${target}`,
                source: source,
                target: target,
                type: edge.type,
                edgeColour: edgeColour,
                label: edgeLabel
            },
            classes: edge.type
        })
    }
    
    return elements
}

/**
 * Convert network to vis-network format
 * Builds nodes from entities and edges from relationships
 * - Genes are large boxes (parent nodes)
 * - Reactions/species with parent are nested inside genes
 * - Standalone reactions/species are shown at top level
 */
export function networkToVisData(network: Network): { nodes: any[], edges: any[] } {
    const nodes: any[] = []
    
    // Determine parent for each entity (reactions/species belong to their gene)
    const getParentGene = (entity: Entity): string | undefined => {
        if (entity.type === 'gene') return undefined
        if (entity.parent) return entity.parent
        
        // If it's a species or reaction, find the gene that produces/uses it
        if (entity.type === 'species') {
            // Find a gene that outputs to this species (mRNA or protein state)
            for (const e of network.entities) {
                if (e.type === 'gene') {
                    const gene = e as any
                    if (gene.mrnaStateId === entity.uid || 
                        gene.proteinStateId === entity.uid ||
                        gene.promoterActiveId === entity.uid ||
                        gene.promoterInactiveId === entity.uid) {
                        return gene.uid
                    }
                }
            }
        }
        
        if (entity.type === 'reaction') {
            // Find a gene that this reaction is associated with
            const reaction = entity as any
            if (reaction.geneId) return reaction.geneId
        }
        
        return undefined
    }
    
    // Build nodes from entities
    for (const entity of network.entities) {
        let color: string
        let size: number
        let shape: string
        
        if (entity.type === 'gene') {
            color = '#4DAF4A'
            size = 200  // Very large for genes (parent nodes)
            shape = 'box'
        } else if (entity.type === 'species') {
            color = '#377EB8'
            size = 20  // Small for species
            shape = 'circle'
        } else if (entity.type === 'reaction') {
            color = '#E41A1C'
            size = 20  // Small for reactions
            shape = 'diamond'
        } else {
            color = '#999999'
            size = 20
            shape = 'circle'
        }
        
        const parentId = getParentGene(entity)
        
        nodes.push({
            id: entity.uid,
            label: entity.label || entity.uid,
            type: entity.type,
            parent: parentId,
            color: { background: color, border: '#000', highlight: '#333' },
            shape,
            size,
            font: { size: 11, multi: true },
            margin: 10
        })
    }
    
    // Create placeholder nodes for edge endpoints that don't exist as entities
    const nodeIds = new Set(nodes.map(n => n.id))
    const edgeNodeIds = new Set<string>()
    
    for (const edge of network.edges) {
        edgeNodeIds.add(edge.source)
        edgeNodeIds.add(edge.target)
    }
    
    for (const nodeId of edgeNodeIds) {
        if (!nodeIds.has(nodeId)) {
            // Infer type from ID pattern
            let type = 'species'
            let color = '#377EB8'
            let shape = 'circle'
            let size = 20
            
            if (nodeId.includes('_transcription')) {
                type = 'reaction'
                color = '#E41A1C'
                shape = 'diamond'
            } else if (nodeId.includes('_translation')) {
                type = 'reaction'
                color = '#E41A1C'
                shape = 'diamond'
            } else if (nodeId.includes('_decay')) {
                type = 'reaction'
                color = '#E41A1C'
                shape = 'diamond'
            } else if (nodeId.includes('promoter')) {
                type = 'species'
                color = '#377EB8'
                shape = 'circle'
            }
            
            nodes.push({
                id: nodeId,
                label: nodeId,
                type,
                color: { background: color, border: '#000', highlight: '#333' },
                shape,
                size,
                font: { size: 11, multi: true },
                margin: 10
            })
            
            nodeIds.add(nodeId)
        }
    }
    
    // Use edges from network (backend generates these)
    const allEdges = network.edges
    
    const visEdges: any[] = []
    for (const edge of allEdges) {
        const arrowDirection = edge.type === 'activation' ? 'to' 
                            : edge.type === 'repression' ? 'from'
                            : edge.type === 'proteolysis' ? 'from'
                            : edge.type === 'output' ? 'to'
                            : 'from'
        
        const color = edge.type === 'activation' ? '#4DAF4A'
                    : edge.type === 'repression' ? '#E41A1C'
                    : edge.type === 'proteolysis' ? '#FF7F00'
                    : edge.type === 'input' ? '#999999'
                    : edge.type === 'output' ? '#666666'
                    : '#999999'
        
        const visEdge: any = {
            from: edge.source,
            to: edge.target,
            label: edge.type,
            color: { color, highlight: '#000' },
            smooth: { type: 'continuous' },
            width: 2
        }
        
        // Set arrow direction
        if (arrowDirection === 'to') {
            visEdge.arrows = 'to'
        } else if (arrowDirection === 'from') {
            visEdge.arrows = 'from'
        }
        
        visEdges.push(visEdge)
    }
    
    return { nodes, edges: visEdges }
}

/**
 * Desaturate and lighten a hex colour for gene group backgrounds
 * Makes colours less vibrant and lighter
 * @param hex - Hex colour string (#RRGGBB)
 * @param saturationFactor - Saturation multiplier (0-1, default 0.5 for 50% saturation)
 * @param lightnessBoost - Lightness increase (0-1, default 0.2 for +20% lightness)
 */
function desaturateAndLighten(hex: string, saturationFactor = 0.8, lightnessBoost = 0.4): string {
    // Parse hex to RGB
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex)
    if (!result) return hex
    
    let r = parseInt(result[1], 16) / 255
    let g = parseInt(result[2], 16) / 255
    let b = parseInt(result[3], 16) / 255
    
    // Convert to HSL
    const max = Math.max(r, g, b)
    const min = Math.min(r, g, b)
    let h = 0, s = 0, l = (max + min) / 2
    
    if (max !== min) {
        const d = max - min
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
        
        switch (max) {
            case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break
            case g: h = ((b - r) / d + 2) / 6; break
            case b: h = ((r - g) / d + 4) / 6; break
        }
    }
    
    // Apply desaturation and lightening
    s = s * saturationFactor
    l = Math.min(l + lightnessBoost, 0.95)
    
    // Convert back to RGB
    let r2, g2, b2
    if (s === 0) {
        r2 = g2 = b2 = l
    } else {
        const hue2rgb = (p: number, q: number, t: number) => {
            if (t < 0) t += 1
            if (t > 1) t -= 1
            if (t < 1/6) return p + (q - p) * 6 * t
            if (t < 1/2) return q
            if (t < 2/3) return p + (q - p) * (2/3 - t) * 6
            return p
        }
        const q = l < 0.5 ? l * (1 + s) : l + s - l * s
        const p = 2 * l - q
        r2 = hue2rgb(p, q, h + 1/3)
        g2 = hue2rgb(p, q, h)
        b2 = hue2rgb(p, q, h - 1/3)
    }
    
    // Convert back to hex
    const toHex = (x: number) => {
        const hex = Math.round(x * 255).toString(16)
        return hex.length === 1 ? '0' + hex : hex
    }
    
    return `#${toHex(r2)}${toHex(g2)}${toHex(b2)}`
}
