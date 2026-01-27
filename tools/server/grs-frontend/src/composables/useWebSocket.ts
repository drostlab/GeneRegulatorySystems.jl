import { ref } from 'vue'
import { config } from '@/config'

export interface WebSocketMessage {
    type: string
    data?: any
    error?: string
    status?: string
    result_id?: string
}

/**
 * useWebSocket - Composable for managing WebSocket connection
 *
 * Handles:
 * - Connection lifecycle (connect, disconnect, reconnect on failure)
 * - Message parsing and routing
 * - Callback registration for different message types
 * - Connection state tracking
 *
 */
export function useWebSocket() {
    const isConnected = ref<boolean>(false)
    let ws: WebSocket | null = null

    // Message handlers
    const messageHandlers = new Map<string, (message: WebSocketMessage) => void>()

    /**
     * Connect to WebSocket server
     * Returns promise that resolves when connection is established
     */
    async function connect(): Promise<void> {
        console.log('[useWebSocket] Connecting...', { isConnected: isConnected.value })

        if (isConnected.value && ws && ws.readyState === WebSocket.OPEN) {
            console.log('[useWebSocket] Already connected')
            return
        }

        return new Promise((resolve, reject) => {
            try {
                const wsUrl = config.getWebSocketUrl()
                console.log('[useWebSocket] WebSocket URL:', wsUrl)

                ws = new WebSocket(wsUrl)

                const timeout = setTimeout(() => {
                    console.error('[useWebSocket] Connection timeout (10s)')
                    reject(new Error('WebSocket connection timeout'))
                }, 10000)

                ws.onopen = () => {
                    clearTimeout(timeout)
                    isConnected.value = true
                    console.log('[useWebSocket] Connected')
                    resolve()
                }

                ws.onmessage = (event: MessageEvent) => {
                    try {
                        const message = JSON.parse(event.data) as WebSocketMessage
                        handleMessage(message)
                    } catch (error) {
                        console.error('[useWebSocket] Failed to parse message:', error)
                    }
                }

                ws.onerror = (error: Event) => {
                    clearTimeout(timeout)
                    console.error('[useWebSocket] Connection error:', error)
                    isConnected.value = false
                    reject(new Error('WebSocket connection error'))
                }

                ws.onclose = () => {
                    console.log('[useWebSocket] Disconnected')
                    isConnected.value = false
                }
            } catch (error) {
                console.error('[useWebSocket] Exception during setup:', error)
                isConnected.value = false
                reject(error)
            }
        })
    }

    /**
     * Disconnect from WebSocket
     */
    function disconnect(): void {
        if (ws) {
            ws.close()
            ws = null
        }
        isConnected.value = false
        console.log('[useWebSocket] Disconnected')
    }

    /**
     * Send a message to the server
     */
    function send(message: Record<string, any>): void {
        if (!ws || ws.readyState !== WebSocket.OPEN) {
            console.error('[useWebSocket] Cannot send - WebSocket not connected')
            return
        }
        ws.send(JSON.stringify(message))
        console.log('[useWebSocket] Sent:', message)
    }

    /**
     * Register handler for specific message type
     */
    function on(messageType: string, handler: (message: WebSocketMessage) => void): void {
        messageHandlers.set(messageType, handler)
        console.debug('[useWebSocket] Registered handler for:', messageType)
    }

    /**
     * Unregister handler for message type
     */
    function off(messageType: string): void {
        messageHandlers.delete(messageType)
        console.debug('[useWebSocket] Unregistered handler for:', messageType)
    }

    /**
     * Handle incoming message by routing to registered handlers
     */
    function handleMessage(message: WebSocketMessage): void {
        const handler = messageHandlers.get(message.type)
        if (handler) {
            handler(message)
        } else {
            console.warn('[useWebSocket] No handler for message type:', message.type)
        }
    }

    return {
        isConnected,
        connect,
        disconnect,
        send,
        on,
        off
    }
}
