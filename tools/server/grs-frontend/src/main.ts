import { createApp } from 'vue'
import { createPinia } from 'pinia'
import piniaPluginPersistedstate from 'pinia-plugin-persistedstate'
import PrimeVue from 'primevue/config'
import Tooltip from 'primevue/tooltip'
import { definePreset } from '@primeuix/themes'
import 'primeicons/primeicons.css'
import './style.css'
import App from './App.vue'
import Aura from '@primeuix/themes/aura'
import { EWatermarkPosition, SciChartDefaults, SciChartSurface } from "scichart";
import { palette } from './config/theme'

SciChartSurface.UseCommunityLicense();
SciChartDefaults.watermarkPosition = EWatermarkPosition.BottomLeft

SciChartDefaults.nativeFontTimeout = 10000
SciChartDefaults.canvasFontFamily = "Montserrat"
SciChartDefaults.useNativeText = false


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
        info: palette.purple
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
                    background: '{neutral.900}',
                    borderColor: '{neutral.500}',
                    color: '{neutral.500}'
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

app.directive('tooltip', Tooltip)

app.mount('#app')
