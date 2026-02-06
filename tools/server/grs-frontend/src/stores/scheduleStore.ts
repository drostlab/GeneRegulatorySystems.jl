import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { Schedule} from '@/types/schedule'
import * as scheduleService from '@/services/scheduleService'
import { computeScheduleKey, extractAllGeneIds } from '@/types/schedule'

export const useScheduleStore = defineStore(
    'schedule',
    () => {

        /**
         * Selected schedule in dropdown (e.g., "example/repressilator" or "user/my-schedule").
         * Used to restore UI selection after navigation. Doesn't auto-load; ScheduleEditor controls that.
         */
        const scheduleKey = computed(() => computeScheduleKey(schedule.value.name, schedule.value.source)) 
        const schedule = ref<Schedule>({
            name: '',
            source: 'user',
            spec: '',
            data: null,
            validationMessages: []
        })

        /**
         * Validation messages for the current schedule
         * Each message includes type (error/warning/info) and content
         */
        const scheduleMessages = computed(() => schedule.value.validationMessages ?? [])

        /**
         * Loading state for schedule operations (loading, validating, parsing)
         */
        const isLoading = ref<boolean>(false)

        const allGenes = computed(() => schedule.value.data ? extractAllGeneIds(schedule.value.data) : null)

        const geneColours = computed(() => schedule.value.data?.vis_metadata.gene_colours ?? null)

        /**
         * Timeline segments from running schedule. Empty if no schedule loaded.
         * Used by NetworkDiagram and timeline UI components.
         * Derived from: schedule.data
         */
        const segments = computed(() => schedule.value.data?.segments || [])

        const isLoaded = computed(() => schedule.value.data !== null)

        async function loadScheduleByKey(key: string): Promise<Schedule> {
            const startTime = performance.now()
            console.debug(`[ScheduleStore] loadScheduleByKey started for: ${key}`)
            console.debug(`[ScheduleStore] Setting isLoading = true`)
            
            isLoading.value = true
            // Clear previous schedule data immediately
            schedule.value.data = null
            console.debug(`[ScheduleStore] Cleared old schedule data`)
            
            try {
                const serviceStart = performance.now()
                const res = await scheduleService.loadScheduleFromKey(key)
                console.debug(`[ScheduleStore] Service call took ${(performance.now() - serviceStart).toFixed(2)}ms`)

                const assignStart = performance.now()
                schedule.value = res
                console.debug(`[ScheduleStore] Store assignment took ${(performance.now() - assignStart).toFixed(2)}ms`)
                console.debug(`[ScheduleStore] Schedule loaded:`, res)
                
                // Log vis_metadata for debugging gene colors
                if (res.data) {
                    if (res.data.vis_metadata) {
                        console.debug(`[ScheduleStore] Schedule vis_metadata:`, res.data.vis_metadata)
                        console.debug(`[ScheduleStore] Gene colours:`, res.data.vis_metadata.gene_colours)
                    } else {
                        console.warn(`[ScheduleStore] No vis_metadata found in schedule data`)
                    }
                } else {
                    console.warn(`[ScheduleStore] No data found in schedule`)
                }
                
                console.debug(`[ScheduleStore] Total loadScheduleByKey time: ${(performance.now() - startTime).toFixed(2)}ms`)
                return schedule.value
            } catch (error) {
                console.error(`[ScheduleStore] Error in loadScheduleByKey:`, error)
                throw error
            } finally {
                console.debug(`[ScheduleStore] Setting isLoading = false`)
                isLoading.value = false
                console.debug(`[ScheduleStore] isLoading is now: ${isLoading.value}`)
            }
        }

        async function loadScheduleBySpec(spec: string, name: string): Promise<Schedule> {
            const startTime = performance.now()
            console.debug(`[ScheduleStore] loadScheduleBySpec started for: ${name}`)
            console.debug(`[ScheduleStore] Setting isLoading = true`)
            
            isLoading.value = true
            // Clear previous schedule data immediately
            schedule.value.data = null
            console.debug(`[ScheduleStore] Cleared old schedule data`)
            
            try {
                const serviceStart = performance.now()
                const res = await scheduleService.loadScheduleFromSpec(spec, name)
                console.debug(`[ScheduleStore] Service call took ${(performance.now() - serviceStart).toFixed(2)}ms`)

                const assignStart = performance.now()
                schedule.value = res
                console.debug(`[ScheduleStore] Store assignment took ${(performance.now() - assignStart).toFixed(2)}ms`)
                
                console.debug(`[ScheduleStore] Total loadScheduleBySpec time: ${(performance.now() - startTime).toFixed(2)}ms`)
                return schedule.value
            } catch (error) {
                console.error(`[ScheduleStore] Error in loadScheduleBySpec:`, error)
                throw error
            } finally {
                console.debug(`[ScheduleStore] Setting isLoading = false`)
                isLoading.value = false
                console.debug(`[ScheduleStore] isLoading is now: ${isLoading.value}`)
            }
        }


        return {
            schedule,
            scheduleKey,
            scheduleMessages,
            isLoading,
            allGenes,
            geneColours,
            segments,
            isLoaded,
            loadScheduleByKey,
            loadScheduleBySpec
        }
    },
    {
        persist: import.meta.env.DEV ? true : false
    }
)

