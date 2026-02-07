import { createApp } from 'vue'
import { createPinia } from 'pinia'
import piniaPluginPersistedstate from 'pinia-plugin-persistedstate'
import PrimeVue from 'primevue/config'
import { definePreset } from '@primeuix/themes'
import 'primeicons/primeicons.css'
import './style.css'
import App from './App.vue'
import Aura from '@primeuix/themes/aura'
import { SciChartSurface } from "scichart";

SciChartSurface.UseCommunityLicense();

const MyPreset = definePreset(Aura, {
    semantic: {
        primary: {
            50: '{red.50}',
            100: '{red.100}',
            200: '{red.200}',
            300: '{red.300}',
            400: '{red.400}',
            500: '{red.500}',
            600: '{red.600}',
            700: '{red.700}',
            800: '{red.800}',
            900: '{red.900}',
            950: '{red.950}'
        },
        info: {
            50:  '#f6f0f9',
            100: '#eadcf1',
            200: '#d4b8e3',
            300: '#bf95d5',
            400: '#b381cb',
            500: '#AA79C1', // base
            600: '#9563ac',
            700: '#7d4e92',
            800: '#653a78',
            900: '#512663',
            950: '#321942'
        }
    },
    components: {
        message: {
        colorScheme: {
            light: {
                info: {
                    background: '{info.50}',
                    borderColor: '{info.200}',
                    color: '{info.700}'
                }
            },
            dark: {
                info: {
                    background: '{info.300}',
                    borderColor: '{info.400}',
                    color: '{info.950}'
                }
            }
        }
        }
    }
})

const app = createApp(App)

const pinia = createPinia()
pinia.use(piniaPluginPersistedstate)
app.use(pinia)
app.use(PrimeVue, {
    theme: {
        preset: MyPreset,
        options: {
            darkModeSelector: '.app-dark'
        }
    }
})

app.mount('#app')
