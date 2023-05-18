include("src/common.jl")
include("src/sysimage/script.jl")
exit(something(SysimageScript.run(), 0))
