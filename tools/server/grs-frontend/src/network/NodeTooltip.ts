/**
 * Node tooltip: shows the full node name on hover via a lightweight DOM tooltip.
 */
import type { Core, EventHandler } from 'cytoscape'

const TOOLTIP_ID = 'cy-node-tooltip'

export class NodeTooltip {
    private cy: Core | null = null
    private tooltip: HTMLDivElement | null = null
    private onMouseOver: EventHandler | null = null
    private onMouseOut: EventHandler | null = null

    attach(cy: Core): void {
        this.cy = cy
        this.tooltip = this.createTooltipElement()

        this.onMouseOver = (evt: any) => {
            const node = evt.target
            const fullName = node.data('id') ?? 'unknown'
            this.tooltip!.textContent = fullName
            this.tooltip!.style.display = 'block'

            const renderedPos = evt.renderedPosition ?? evt.position
            this.tooltip!.style.left = `${renderedPos.x + 12}px`
            this.tooltip!.style.top = `${renderedPos.y - 20}px`
        }

        this.onMouseOut = () => {
            this.tooltip!.style.display = 'none'
        }

        cy.on('mouseover', 'node', this.onMouseOver)
        cy.on('mouseout', 'node', this.onMouseOut)
    }

    destroy(): void {
        if (this.cy && this.onMouseOver) {
            this.cy.off('mouseover', 'node', this.onMouseOver)
        }
        if (this.cy && this.onMouseOut) {
            this.cy.off('mouseout', 'node', this.onMouseOut)
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
            padding: '4px 10px',
            background: '#333',
            color: '#fff',
            borderRadius: '4px',
            fontSize: '12px',
            fontFamily: 'Montserrat, sans-serif',
            pointerEvents: 'none',
            zIndex: '9999',
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
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
