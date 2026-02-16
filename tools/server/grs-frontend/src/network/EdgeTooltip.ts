/**
 * Edge tooltip: shows the edge kind on hover via a lightweight DOM tooltip.
 */
import type { Core, EventHandler } from 'cytoscape'

const TOOLTIP_ID = 'cy-edge-tooltip'

export class EdgeTooltip {
    private cy: Core | null = null
    private tooltip: HTMLDivElement | null = null
    private onMouseOver: EventHandler | null = null
    private onMouseOut: EventHandler | null = null

    attach(cy: Core): void {
        this.cy = cy
        this.tooltip = this.createTooltipElement()

        this.onMouseOver = (evt: any) => {
            const edge = evt.target
            const kind = edge.data('kind') ?? 'unknown'
            this.tooltip!.textContent = kind
            this.tooltip!.style.display = 'block'

            const renderedPos = evt.renderedPosition ?? evt.position
            this.tooltip!.style.left = `${renderedPos.x + 12}px`
            this.tooltip!.style.top = `${renderedPos.y - 20}px`
        }

        this.onMouseOut = () => {
            this.tooltip!.style.display = 'none'
        }

        cy.on('mouseover', 'edge', this.onMouseOver)
        cy.on('mouseout', 'edge', this.onMouseOut)
    }

    destroy(): void {
        if (this.cy && this.onMouseOver) {
            this.cy.off('mouseover', 'edge', this.onMouseOver)
        }
        if (this.cy && this.onMouseOut) {
            this.cy.off('mouseout', 'edge', this.onMouseOut)
        }
        this.tooltip?.remove()
        this.tooltip = null
        this.onMouseOver = null
        this.onMouseOut = null
        this.cy = null
    }

    private createTooltipElement(): HTMLDivElement {
        // Re-use existing tooltip if present
        let el = document.getElementById(TOOLTIP_ID) as HTMLDivElement | null
        if (el) return el

        el = document.createElement('div')
        el.id = TOOLTIP_ID
        Object.assign(el.style, {
            position: 'absolute',
            display: 'none',
            padding: '3px 8px',
            background: '#333',
            color: '#fff',
            borderRadius: '4px',
            fontSize: '11px',
            fontFamily: 'Montserrat, sans-serif',
            pointerEvents: 'none',
            zIndex: '9999',
            whiteSpace: 'nowrap',
        })

        // Append to cytoscape container's parent so positioning is relative
        const container = this.cy?.container()
        if (container) {
            container.style.position = 'relative'
            container.appendChild(el)
        } else {
            document.body.appendChild(el)
        }

        return el
    }
}
