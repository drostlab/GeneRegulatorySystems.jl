/**
 * Monaco Editor Composable – Encapsulates Monaco editor lifecycle
 *
 * Responsibilities:
 * - Initialize Monaco from CDN
 * - Create and manage editor instance
 * - Handle theme switching
 * - Content change callbacks
 *
 * Usage:
 * ```typescript
 * const { editor, initializeMonaco } = useMonacoEditor(container, onContentChange)
 * await initializeMonaco()
 * ```
 */

import { shallowRef } from 'vue'

export function useMonacoEditor(
    containerId: string,
    onContentChange?: (content: string) => void
) {
    const editor = shallowRef<any>(null)

    /**
     * Define custom Atom One themes
     */
    function defineAtomThemes(monacoInstance: any) {
        monacoInstance.editor.defineTheme('atom-one-dark', {
            base: 'vs-dark',
            inherit: true,
            rules: [
                { token: 'string.key.json', foreground: 'e06c75' },
                { token: 'string.value.json', foreground: '98c379' },
                { token: 'number.json', foreground: 'd19a66' },
                { token: 'keyword.json', foreground: 'c678dd' },
                { token: 'comment.json', foreground: '5c6370' },
                { token: 'delimiter.json', foreground: 'abb2bf' },
                { token: 'delimiter.bracket.json', foreground: 'e06c75' }
            ],
            colors: {
                'editor.background': '#1d1f21'
            }
        })

        monacoInstance.editor.defineTheme('atom-one-light', {
            base: 'vs',
            inherit: true,
            rules: [
                { token: 'string.key.json', foreground: 'e45649' },
                { token: 'string.value.json', foreground: '50a14f' },
                { token: 'number.json', foreground: '986801' },
                { token: 'keyword.json', foreground: 'a626a4' },
                { token: 'comment.json', foreground: 'a0a1a7' },
                { token: 'delimiter.json', foreground: '383a42' },
                { token: 'delimiter.bracket.json', foreground: 'e45649' }
            ],
            colors: {
                'editor.background': '#fafafa',
                'editor.foreground': '#383a42',
                'editor.lineNumbersBackground': '#fafafa',
                'editor.lineNumbersForeground': '#9d9d9f',
                'editor.selectionBackground': '#e5e5e680',
                'editor.inactiveSelectionBackground': '#e5e5e640',
                'editor.lineHighlightBackground': '#f0f0f1',
                'editorCursor.foreground': '#4078f2',
                'editorWhitespace.foreground': '#d0d0d0'
            }
        })
    }

    /**
     * Create the editor instance
     */
    function createEditor(monacoInstance: any, initialContent: string, isEditing: boolean) {
        const container = document.getElementById(containerId)
        if (!container || editor.value) return

        const isDark = document.documentElement.classList.contains('app-dark')

        try {
            editor.value = monacoInstance.editor.create(container, {
                value: initialContent,
                language: 'json',
                theme: isDark ? 'atom-one-dark' : 'atom-one-light',
                automaticLayout: true,
                minimap: { enabled: false },
                fontSize: 11,
                fontFamily: "'Fira Code', monospace",
                scrollBeyondLastLine: false,
                wordWrap: 'on',
                readOnly: !isEditing,
                cursorStyle: isEditing ? 'line' : 'hidden',
                scrollbar: {
                    vertical: 'auto',
                    horizontal: 'auto',
                    useShadows: false,
                    verticalSliderSize: 6,
                    horizontalSliderSize: 6
                }
            })

            editor.value.onDidChangeModelContent(() => {
                // Only process changes if explicitly in edit mode
                // Don't call onContentChange during programmatic setValue() calls
                if (editor.value) {
                    const newContent = editor.value.getValue()
                    if (onContentChange)
                        onContentChange(newContent)
                }
            })

            // Setup theme switching on dark mode toggle
            const observer = new MutationObserver((mutations) => {
                mutations.forEach((mutation) => {
                    if (mutation.attributeName === 'class' && editor.value) {
                        const newIsDark = document.documentElement.classList.contains('app-dark')
                        const newTheme = newIsDark ? 'atom-one-dark' : 'atom-one-light'
                        monacoInstance.editor.setTheme(newTheme)
                    }
                })
            })

            observer.observe(document.documentElement, { attributes: true })

            // Store observer for cleanup
            ;(editor.value as any).__themeObserver = observer
        } catch (err) {
            console.error('[useMonacoEditor] Failed to create editor:', err)
            editor.value = null
        }
    }

    /**
     * Initialize Monaco from CDN
     */
    function init(initialContent: string = '', isEditing: boolean = false): Promise<void> {
        return new Promise((resolve, reject) => {
            const monacoGlobal = (window as any).monaco
            if (typeof monacoGlobal !== 'undefined') {
                defineAtomThemes(monacoGlobal)
                createEditor(monacoGlobal, initialContent, isEditing)
                resolve()
                return
            }

            const script = document.createElement('script')
            script.src = 'https://cdn.jsdelivr.net/npm/monaco-editor@0.55.1/min/vs/loader.min.js'
            script.onload = () => {
                // @ts-ignore
                require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.55.1/min/vs' } })
                // @ts-ignore
                require(['vs/editor/editor.main'], () => {
                    const monacoInstance = (window as any).monaco
                    defineAtomThemes(monacoInstance)
                    createEditor(monacoInstance, initialContent, isEditing)
                    resolve()
                })
            }
            script.onerror = () => {
                console.error('[useMonacoEditor] Failed to load Monaco editor from CDN')
                reject(new Error('Failed to load Monaco editor'))
            }
            document.head.appendChild(script)
        })
    }

    /**
     * Update editor content
     */
    function setValue(content: string) {
        if (!editor.value) {
            console.warn('[useMonacoEditor] editor.value is null/undefined, cannot setValue')
            return
        }
        editor.value.setValue(content)
    }

    function getContent(): string {
        return editor.value?.getModel()?.getValue() ?? ' '
    }

    /**
     * Update editor options (e.g., readOnly)
     */
    function updateOptions(options: any) {
        if (editor.value) {
            editor.value.updateOptions(options)
        }
    }

    /**
     * Cleanup: disconnect observers and dispose editor
     */
    function dispose() {
        if (editor.value) {
            const observer = (editor.value as any).__themeObserver
            if (observer) {
                observer.disconnect()
            }
            editor.value.dispose()
            editor.value = null
        }
    }

    return {
        init,
        setValue,
        getContent,
        updateOptions,
        dispose
    }
}
