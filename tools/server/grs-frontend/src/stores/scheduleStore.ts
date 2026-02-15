import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { Schedule } from '@/types/schedule'
import type { UnionNetwork } from '@/types/network'
import * as scheduleService from '@/services/scheduleService'
import {
    computeScheduleKey, extractAllGeneIds, getSpeciesForGene,
    getSpeciesForType, getTimeExtent, getUniqueModelPaths
} from '@/types/schedule'
import type { SpeciesType } from '@/types/schedule'
import type { TimeseriesMetadata } from '@/types/simulation'
import { useViewerStore } from './viewerStore'

export const useScheduleStore = defineStore(
    'schedule',
    () => {
        const scheduleKey = computed(() => computeScheduleKey(schedule.value.name, schedule.value.source))
        const schedule = ref<Schedule>({
            name: '',
            source: 'user',
            spec: '',
            data: null,
            validationMessages: []
        })

        const scheduleMessages = computed(() => schedule.value.validationMessages ?? [])
        const isLoading = ref<boolean>(false)

        const allGenes = computed(() => schedule.value.data ? extractAllGeneIds(schedule.value.data) : null)
        const geneColours = computed(() => schedule.value.data?.gene_colours ?? null)
        const segments = computed(() => schedule.value.data?.segments || [])
        const isLoaded = computed(() => schedule.value.data !== null)

        const timeseriesMetadata = computed((): TimeseriesMetadata | null => {
            if (!schedule.value.data) return null
            return {
                species_gene_mapping: schedule.value.data.species_gene_mapping,
                gene_colours: schedule.value.data.gene_colours,
                time_extent: getTimeExtent(schedule.value.data.segments)
            }
        })

        const unionNetwork = ref<UnionNetwork | null>(null)

        /** All model paths available in the union network. */
        const modelPaths = computed((): string[] => {
            if (!unionNetwork.value) return []
            return Object.keys(unionNetwork.value.model_exclusions)
        })

        function clearNetwork(): void {
            unionNetwork.value = null
            const viewerStore = useViewerStore()
            viewerStore.setActiveModelPath(null)
            viewerStore.selectSegments(null)
        }

        async function fetchUnionNetwork(): Promise<UnionNetwork | null> {
            if (!schedule.value.data) return null
            if (unionNetwork.value) return unionNetwork.value

            const segs = schedule.value.data.segments
            const result = await scheduleService.fetchUnionNetwork(schedule.value.spec, segs)
            unionNetwork.value = result

            // Auto-select first model path
            const viewerStore = useViewerStore()
            const paths = getUniqueModelPaths(segs)
            if (paths.length > 0 && !viewerStore.activeModelPath) {
                viewerStore.setActiveModelPath(paths[0]!)
            }

            console.debug(`[ScheduleStore] Union network loaded: ${result.nodes.length} nodes, ${result.links.length} links, ${Object.keys(result.model_exclusions).length} models`)
            return result
        }

        async function loadScheduleByKey(key: string): Promise<Schedule> {
            isLoading.value = true
            clearNetwork()
            schedule.value.data = null

            try {
                const res = await scheduleService.loadScheduleFromKey(key)
                schedule.value = res
                console.debug(`[ScheduleStore] Loaded schedule: ${key}`)
                return schedule.value
            } finally {
                isLoading.value = false
            }
        }

        async function loadScheduleBySpec(spec: string, name: string): Promise<Schedule> {
            isLoading.value = true
            clearNetwork()
            schedule.value.data = null

            try {
                const res = await scheduleService.loadScheduleFromSpec(spec, name)
                schedule.value = res
                console.debug(`[ScheduleStore] Loaded schedule from spec: ${name}`)
                return schedule.value
            } finally {
                isLoading.value = false
            }
        }

        function getSpeciesForGeneId(gene: string): string[] {
            if (!schedule.value.data) return []
            return getSpeciesForGene(schedule.value.data, gene)
        }

        function getSpeciesForSpeciesType(speciesType: SpeciesType): string[] {
            if (!schedule.value.data) return []
            return getSpeciesForType(schedule.value.data, speciesType)
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
            timeseriesMetadata,
            unionNetwork,
            modelPaths,
            loadScheduleByKey,
            loadScheduleBySpec,
            fetchUnionNetwork,
            getSpeciesForGeneId,
            getSpeciesForSpeciesType
        }
    },
    {
        persist: import.meta.env.DEV ? true : false
    }
)

