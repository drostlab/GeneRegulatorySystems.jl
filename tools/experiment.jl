# Conditionally import the script from the sysimage if available, otherwise
# load it along with (only) its dependencies;
# see [`GeneRegulatorySystemsTools`](@ref).
if "GeneRegulatorySystemsTools" in (
    first(entry).name for entry in Base.loaded_modules
)
    import GeneRegulatorySystemsTools: ExperimentScript
else
    include("src/common.jl")
    include("src/scripts/experiment.jl")
end

exit(something(ExperimentScript.run(), 0))
