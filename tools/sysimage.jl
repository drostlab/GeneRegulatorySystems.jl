include("src/common.jl")
include("src/scripts/sysimage.jl")
exit(something(SysimageScript.run(), 0))
