import { SciChartJSDarkv2Theme, SciChartJSLightTheme } from 'scichart'


// TODO: add more styiling here perhaps?
function createTheme() {
    const isDarkMode = document.documentElement.classList.contains('app-dark')
    return isDarkMode ? new SciChartJSDarkv2Theme() : new SciChartJSLightTheme()
}

export const appTheme = createTheme()