using HypertextLiteral: @htl

struct DarkMode end

Base.get(::DarkMode) = false

Base.show(io::IO, ::MIME"text/html", ::DarkMode) =
    show(io, MIME"text/html"(), @htl("""
<span>
<script>
    const root = currentScript.parentElement
    const media = window.matchMedia("(prefers-color-scheme: dark)")

    const update = () => {
        root.value = media.matches
        root.dispatchEvent(new CustomEvent("input"))
    }

    media.addEventListener("change", update)
    update()

    invalidation.then(() =>
        media.removeEventListener("change", update)
    )
</script>
</span>
"""))
