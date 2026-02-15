import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { Schedule } from '@/types/schedule'
import type { Network } from '@/types/network'
import * as scheduleService from '@/services/scheduleService'
import {
    computeScheduleKey, extractAllGeneIds, getSpeciesForGene,
    getSpeciesForType, getTimeExtent
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

        const networks = ref<Map<string, Network>>(new Map())

        const activeNetwork = computed((): Network | null => {
            const viewerStore = useViewerStore()
            if (!viewerStore.activeModelPath) return null
            return networks.value.get(viewerStore.activeModelPath) ?? null
        })

        function clearNetworks(): void {
            networks.value = new Map()
            const viewerStore = useViewerStore()
            viewerStore.setActiveModelPath(null)
            viewerStore.selectSegments(null)
        }

        async function fetchNetwork(modelPath: string): Promise<Network> {
            const cached = networks.value.get(modelPath)
            if (cached) {
                const viewerStore = useViewerStore()
                viewerStore.setActiveModelPath(modelPath)
                return cached
            }

            let network: Network
            if (schedule.value.source === 'user' || schedule.value.source === 'snapshot') {
                network = await scheduleService.fetchNetworkFromSpec(schedule.value.spec, modelPath)
            } else {
                network = await scheduleService.fetchNetwork(schedule.value.source, schedule.value.name, modelPath)
            }

            networks.value.set(modelPath, network)
            const viewerStore = useViewerStore()
            viewerStore.setActiveModelPath(modelPath)
            return network
        }

        async function loadScheduleByKey(key: string): Promise<Schedule> {
            isLoading.value = true
            clearNetworks()
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
            clearNetworks()
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
            networks,
            activeNetwork,
            loadScheduleByKey,
            loadScheduleBySpec,
            fetchNetwork,
            getSpeciesForGeneId,
            getSpeciesForSpeciesType
        }
    },
    {
        persist: import.meta.env.DEV ? true : false
    }
)

