module PageState

using HypertextLiteral
import Bonito

struct Shared
    key::String
end

const STORE = """
    if (!window.__grs_page_state?.connect) {
        const values = new Map()
        const listeners = new Map()

        const same = (a, b) =>
            a.length === b.length && a.every((value, i) => value === b[i])

        const store = {
            get: key => values.get(key) ?? [],

            set(key, next, source) {
                const previous = store.get(key)
                const incoming = new Set(next)
                const ordered = [
                    ...previous.filter(value => incoming.has(value)),
                    ...next.filter(value => !previous.includes(value)),
                ]
                if (same(previous, ordered)) return

                values.set(key, ordered)
                for (const listener of listeners.get(key) ?? []) {
                    if (listener.source !== source) listener.fn(ordered)
                }
            },

            connect(key, source) {
                const entries = new Set()
                return {
                    get: () => store.get(key),
                    set: next => store.set(key, next, source),
                    changed(fn) {
                        const entry = { source, fn }
                        if (!listeners.has(key)) listeners.set(key, new Set())
                        listeners.get(key).add(entry)
                        entries.add(entry)
                        fn(store.get(key))
                    },
                    dispose() {
                        for (const entry of entries) listeners.get(key).delete(entry)
                    },
                }
            },
        }

        window.__grs_page_state = store
    }
"""

const RUNTIME = @htl("""
<span>
<script>$(HypertextLiteral.JavaScript(STORE))</script>
</span>
""")

bridge(shared::Shared) = @htl("""
<span>
$(RUNTIME)
<script>
    const root = currentScript.parentElement
    const state = window.__grs_page_state.connect($(shared.key), "pluto")
    let timer
    let sent = null

    const same = (a, b) =>
        a !== null && a.length === b.length && a.every((value, i) => value === b[i])

    const emit = () => {
        if (same(sent, state.get())) return

        sent = [...state.get()]
        root.value = sent
        root.dispatchEvent(new CustomEvent("input"))
    }

    state.changed(() => {
        clearTimeout(timer)
        timer = setTimeout(emit, 200)
    })

    sent = [...state.get()]
    root.value = sent

    invalidation.then(() => {
        clearTimeout(timer)
        state.dispose()
    })
</script>
</span>
""")

picker(shared::Shared, options; size=3) = @htl("""
<span style="display: inline-block;">
$(RUNTIME)
<input type="search" size="1" style="display: block; width: 100%; box-sizing: border-box; margin-bottom: 2px; font-family: inherit;">
<select multiple size=$(size) style="display: block; width: 100%; box-sizing: border-box;" title="Cmd+Click or Ctrl+Click to select multiple items.">
    $((@htl("<option value=$(option)>$(option)</option>") for option in options))
</select>
<script>
    const select = currentScript.parentElement.querySelector("select")
    const search = currentScript.parentElement.querySelector("input")
    const state = window.__grs_page_state.connect($(shared.key), "picker")

    search.addEventListener("input", () => {
        const query = search.value.trim().toLowerCase()
        for (const option of select.options)
            option.hidden = query !== "" &&
                !option.value.toLowerCase().includes(query) &&
                !option.selected
    })

    select.addEventListener("input", () =>
        state.set([...select.selectedOptions].map(option => option.value))
    )

    state.changed(values => {
        const wanted = new Set(values)
        for (const option of select.options) option.selected = wanted.has(option.value)
    })

    invalidation.then(state.dispose)
</script>
</span>
""")

choice(shared::Shared, options) = @htl("""
<span>
$(RUNTIME)
<select>
    $((@htl("<option value=$(first(option))>$(last(option))</option>") for option in options))
</select>
<script>
    const select = currentScript.parentElement.querySelector("select")
    const state = window.__grs_page_state.connect($(shared.key), "choice")

    state.changed(values => {
        select.value = values[0] ?? ""
        if (select.value !== (values[0] ?? "")) state.set([])
    })
    select.addEventListener("change", () =>
        state.set(select.value === "" ? [] : [select.value])
    )

    invalidation.then(state.dispose)
</script>
</span>
""")

function link(shared::Shared, observable)
    anchor = Bonito.DOM.span()
    Bonito.DOM.span(anchor, Bonito.js"""
        $(Bonito.JSString(STORE))
        const state = window.__grs_page_state.connect($(shared.key), "makie")
        const anchor = $(anchor)
        const alive = () => anchor.isConnected || (state.dispose(), false)
        state.changed(values => {
            if (!alive()) return
            const value = values[0] ?? ""
            if (value !== $(observable).value) $(observable).notify(value)
        })
        $(observable).on(value => alive() && state.set(value === "" ? [] : [value]))
    """)
end

sync(shared::Shared, view) = @htl("""
<span>
$(RUNTIME)
$(view)
<script>
    const root = currentScript.parentElement
    const state = window.__grs_page_state.connect($(shared.key), "cytoscape")

    let selection = null

    root.addEventListener("cytoscape:ready", event => {
        selection = event.detail.selection
        selection.set(state.get())
    })
    root.addEventListener("cytoscape:selection", event =>
        state.set(event.detail.selection)
    )

    state.changed(values => selection?.set(values))

    invalidation.then(state.dispose)
</script>
</span>
""")

end
