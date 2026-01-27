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
    const { source, name } = parseScheduleKey(key)
    try {
        // Fetch full Schedule object with validation and visualization data
        const schedule = await apiFetchJson<Schedule>(
            `/schedules/${source}/${name}`,
            {
                method: 'GET'
            }
        )
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
    try {
        // Send spec to validation endpoint, get back full Schedule with validation messages
        const schedule = await apiFetchJson<Schedule>(
            '/schedules/load',
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ schedule_name: name, schedule_spec: spec })
            }
        )
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
