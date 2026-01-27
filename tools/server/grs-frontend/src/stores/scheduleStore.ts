import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { Schedule} from '@/types/schedule'
import * as scheduleService from '@/services/scheduleService'
import { computeScheduleKey } from '@/types/schedule'

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

        const geneColours = computed(() => schedule.value.data?.visMetadata.geneColours ?? null)

        /**
         * Timeline segments from running schedule. Empty if no schedule loaded.
         * Used by NetworkDiagram and timeline UI components.
         * Derived from: schedule.data
         */
        const segments = computed(() => schedule.value.data?.segments || [])

        /**
         * Checks whether the schedule data is valid (loaded)
         */
        const isValid = computed(() => schedule.value.data !== null)

        async function loadScheduleByKey(key: string): Promise<Schedule> {
            isLoading.value = true
            // Clear previous validation messages
            schedule.value.validationMessages = []
            try {
                const res = await scheduleService.loadScheduleFromKey(key)

                schedule.value = res
                
                return schedule.value
            } finally {
                isLoading.value = false
            }
        }

        async function loadScheduleBySpec(spec: string, name: string): Promise<Schedule> {
            isLoading.value = true
            // Clear previous validation messages
            schedule.value.validationMessages = []
            try {
                const res = await scheduleService.loadScheduleFromSpec(spec, name)

                schedule.value = res
                
                return schedule.value
            } finally {
                isLoading.value = false
            }
        }


        return {
            schedule,
            scheduleKey,
            scheduleMessages,
            isLoading,
            geneColours,
            segments,
            isValid,
            loadScheduleByKey,
            loadScheduleBySpec
        }
    },
    {
        persist: import.meta.env.DEV ? true : false
    }
)

