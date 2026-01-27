/**
 * API utilities - centralized error handling and retry logic
 */

import { config } from '@/config'

export interface FetchOptions extends RequestInit {
    maxRetries?: number
    retryDelay?: number
    timeout?: number
}

/**
 * Centralized fetch wrapper with error handling, retry logic, and timeout
 * @param endpoint - The API endpoint (base URL will be prepended)
 * @param options - Fetch options (+ maxRetries, retryDelay, timeout)
 * @returns Fetch response
 * @throws Error if request fails after retries
 */
export async function apiFetch(endpoint: string, options: FetchOptions = {}): Promise<Response> {
    const url = `${config.API_BASE}${endpoint}`
    const { maxRetries = 3, retryDelay = 100000, timeout = 30000, ...fetchOptions } = options

    let lastError: Error = new Error('Unknown error')

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            const controller = new AbortController()
            const timeoutId = setTimeout(() => controller.abort(), timeout)

            try {
                const response = await fetch(url, {
                    ...fetchOptions,
                    signal: controller.signal
                })

                clearTimeout(timeoutId)

                // Don't retry on client errors (4xx), only on server errors (5xx) or network issues
                if (!response.ok && response.status >= 500) {
                    if (attempt < maxRetries) {
                        console.warn(
                            `[API] Retrying ${url} (attempt ${attempt + 1}/${maxRetries + 1}) - Status: ${response.status}`
                        )
                        await delay(retryDelay * Math.pow(2, attempt)) // Exponential backoff
                        continue
                    }
                }

                return response
            } catch (e) {
                clearTimeout(timeoutId)
                throw e
            }
        } catch (error) {
            lastError = error instanceof Error ? error : new Error(String(error))

            // Don't retry on abort signal or if it's the last attempt
            if (attempt === maxRetries || lastError.name === 'AbortError') {
                break
            }

            console.warn(
                `[API] Retrying ${url} (attempt ${attempt + 1}/${maxRetries + 1}) - Error: ${lastError.message}`
            )
            await delay(retryDelay * Math.pow(2, attempt)) // Exponential backoff
        }
    }

    throw lastError
}

/**
 * Helper to delay for retry backoff
 */
function delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms))
}

/**
 * Parse API error response
 */
export async function parseApiError(response: Response): Promise<string> {
    try {
        const data = (await response.json()) as { error?: string; message?: string }
        return data.error || data.message || `HTTP ${response.status}`
    } catch {
        return `HTTP ${response.status}: ${response.statusText}`
    }
}

/**
 * Fetch JSON with error handling
 * @param endpoint - The API endpoint
 * @param options - Fetch options
 * @returns Parsed JSON response
 */
export async function apiFetchJson<T = any>(
    endpoint: string,
    options: FetchOptions = {}
): Promise<T> {
    const response = await apiFetch(endpoint, options)
    if (!response.ok) {
        const error = await parseApiError(response)
        throw new Error(`API Error: ${error}`)
    }
    return (await response.json()) as T
}

/**
 * Fetch text with error handling
 * @param endpoint - The API endpoint
 * @param options - Fetch options
 * @returns Response as text
 */
export async function apiFetchText(endpoint: string, options: FetchOptions = {}): Promise<string> {
    const response = await apiFetch(endpoint, options)
    if (!response.ok) {
        const error = await parseApiError(response)
        throw new Error(`API Error: ${error}`)
    }
    return response.text()
}
