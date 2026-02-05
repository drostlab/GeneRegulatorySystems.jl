/**
 * Schedule Service – API integration for schedule operations
 *
 * Responsibilities:
 * - Load and validate schedules from backend
 * - Upload and persist schedules
 * - Fetch available schedules (returns keys in "source/name" format)
 * - Validate and generate schedule data from spec
 *
 * Uses schedule keys (format: "source/name") for persistent identification.
 * All endpoints return Schedule objects with validation messages included.
 * Used by: scheduleStore
 */

import { apiFetchJson, apiFetchText} from '@/utils/api'
import { parseScheduleKey, type Schedule} from '@/types/schedule'

export async function fetchAvailableSchedules(): Promise<string[]> {
    const data = await apiFetchJson<string[]>(
        '/schedules'
    )
    return data
}

export async function loadScheduleFromKey(key: string): Promise<Schedule> {
    const startTime = performance.now()
    console.debug(`[ScheduleService] Loading schedule from key: ${key}`)
    
    const { source, name } = parseScheduleKey(key)
    try {
        const fetchStart = performance.now()
        console.debug(`[ScheduleService] About to call apiFetchJson for ${source}/${name}`)
        // Fetch full Schedule object with validation and visualization data
        const schedule = await apiFetchJson<Schedule>(
            `/schedules/${source}/${name}`,
            {
                method: 'GET'
            }
        )
        console.debug(`[ScheduleService] apiFetchJson returned, took ${(performance.now() - fetchStart).toFixed(2)}ms`)
        console.debug(`[ScheduleService] Schedule object received, type: ${typeof schedule}, has data: ${schedule?.data !== null}`)
        
        if (schedule.data) {
            const networkParseStart = performance.now()
            const nodeCount = schedule.data.segments.reduce((sum, seg) => sum + (seg.network?.nodes?.length || 0), 0)
            const linkCount = schedule.data.segments.reduce((sum, seg) => sum + (seg.network?.links?.length || 0), 0)
            console.debug(`[ScheduleService] Schedule has ${schedule.data.segments.length} segments, ${nodeCount} total nodes, ${linkCount} total links`)
            console.debug(`[ScheduleService] Network data parsing took ${(performance.now() - networkParseStart).toFixed(2)}ms`)
        }
        
        console.debug(`[ScheduleService] Total load time: ${(performance.now() - startTime).toFixed(2)}ms`)
        return schedule
    } catch (error) {
        console.error('[ScheduleService] Error fetching schedule from key:', error)
        throw error
    }
}

export async function getScheduleSpec(key: string): Promise<string> {
    const { source, name } = parseScheduleKey(key)

    // Fetch raw schedule JSON
    const spec = await apiFetchText(`/schedules/${source}/${encodeURIComponent(name)}/spec`)
    return spec
}

export async function loadScheduleFromSpec(spec: string, name: string): Promise<Schedule> {
    const startTime = performance.now()
    console.debug(`[ScheduleService] Loading schedule from spec (${spec.length} chars)`)
    
    try {
        const fetchStart = performance.now()
        // Send spec to validation endpoint, get back full Schedule with validation messages
        const schedule = await apiFetchJson<Schedule>(
            '/schedules/load',
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ schedule_name: name, schedule_spec: spec })
            }
        )
        console.debug(`[ScheduleService] API processing took ${(performance.now() - fetchStart).toFixed(2)}ms`)
        
        if (schedule.data) {
            const nodeCount = schedule.data.segments.reduce((sum, seg) => sum + (seg.network?.nodes?.length || 0), 0)
            const linkCount = schedule.data.segments.reduce((sum, seg) => sum + (seg.network?.links?.length || 0), 0)
            console.debug(`[ScheduleService] Generated ${schedule.data.segments.length} segments, ${nodeCount} total nodes, ${linkCount} total links`)
        }
        
        console.debug(`[ScheduleService] Total spec load time: ${(performance.now() - startTime).toFixed(2)}ms`)
        return schedule
    } catch (error) {
        console.error('[ScheduleService] Error loading schedule from spec:', error)
        throw error
    }
}

export async function uploadSchedule(spec: string, name: string): Promise<Schedule> {
    // Send spec to upload endpoint, get back full Schedule with validation messages
    const schedule = await apiFetchJson<Schedule>(
        '/schedules/upload',
        {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ schedule_name: name, schedule_spec: spec })
        }
    )
    return schedule
}
