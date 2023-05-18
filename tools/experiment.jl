# Conditionally import the script from the sysimage if available:
if "GeneRegulatorySystemsTools" in (
    first(entry).name for entry in Base.loaded_modules
)
    import GeneRegulatorySystemsTools: ExperimentScript
else
    include("src/experiment/script.jl")
end

exit(something(ExperimentScript.run(), 0))
