/**
 * Application Configuration
 * Centralised configuration for API endpoints and other settings
 */

const API_HOST = import.meta.env.VITE_API_HOST || 'localhost:8000'
const API_PROTOCOL = import.meta.env.VITE_API_PROTOCOL || 'http'
const WS_PROTOCOL = import.meta.env.VITE_WS_PROTOCOL || 'ws'

export const config = {
    /**
     * API base URL for HTTP requests
     */
    API_BASE: `${API_PROTOCOL}://${API_HOST}`,

    /**
     * WebSocket protocol for simulations
     */
    WS_PROTOCOL,

    /**
     * Get WebSocket URL for persistent connection
     * Single session architecture: all clients use /ws
     */
    getWebSocketUrl: () => {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
        return `${protocol}//${API_HOST}/ws`
    },

}

export default config
