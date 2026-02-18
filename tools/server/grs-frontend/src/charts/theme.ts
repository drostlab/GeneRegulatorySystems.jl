/**
 * SciChart theme accessor.
 *
 * Returns the IThemeProvider from the centralised theme for the current mode.
 * Used by MainChart and BasePanel at surface creation time.
 */

import { getTheme } from '@/config/theme'

/** Get the SciChart theme for the current mode. */
export function getSciChartTheme(isDark: boolean) {
    return getTheme(isDark).sciChartTheme
}