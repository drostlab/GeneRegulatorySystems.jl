# Conditionally import the script from the sysimage if available:
if "GeneRegulatorySystemsTools" in (
    first(entry).name for entry in Base.loaded_modules
)
    import GeneRegulatorySystemsTools: InspectScript
else
    include("src/inspect/script.jl")
end

exit(something(InspectScript.run(), 0))
