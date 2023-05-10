# Conditionally import the script from the sysimage if available, otherwise
# load it along with (only) its dependencies;
# see [`GeneRegulatorySystemsTools`](@ref).
if "GeneRegulatorySystemsTools" in (
    first(entry).name for entry in Base.loaded_modules
)
    import GeneRegulatorySystemsTools: InspectScript
else
    include("src/common.jl")
    include("src/visualization.jl")
    include("src/scripts/inspect.jl")
end

exit(something(InspectScript.run(), 0))
