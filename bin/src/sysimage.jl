module Sysimage

import ..GeneRegulatorySystemsTools

import Pkg

using ArgParse
import GeneRegulatorySystems
import PackageCompiler
import Scratch

const PROJECT = Pkg.project().path
const SCRATCHSPACE = Scratch.scratch_path(
    Scratch.find_uuid(GeneRegulatorySystems),
    "sysimages",
)

settings() = @add_arg_table! ArgParseSettings() begin
    "--compile"
        help = "If given, compile a new sysimage."
        action = :store_true

    "--sink"
        help = """
            Where to place the resulting shared object;
            scratchspace is "$SCRATCHSPACE",
            version is "$(GeneRegulatorySystemsTools.repository_version())"
            """
        default = "{SCRATCHSPACE}/{VERSION}.so"

    "--workload"
        help = """
            The example execution that determines what to bake into the
            sysimage.
            """
        default = "$(@__DIR__)/precompile_workload.jl"

    "--invocation"
        help = """
            If given, write a shell command to standard output that starts
            Julia with the appropriate sysimage.
            """
        action = :store_true
end

function main(;
    compile,
    sink,
    workload,
    invocation,
)
    compile || invocation || ArgParse.show_help(settings())

    location = replace(
        sink,
        "{SCRATCHSPACE}" => SCRATCHSPACE,
        "{VERSION}" => GeneRegulatorySystemsTools.repository_version(),
    )
    
    if compile
        mkpath(dirname(location))
        if startswith(sink, "{SCRATCHSPACE}/")
            Scratch.track_scratch_access(
                Scratch.find_uuid(GeneRegulatorySystems),
                "sysimages"
            )
        end
        @info "About to compile sysimage" location Base.julia_cmd()
        @time PackageCompiler.create_sysimage(;
            sysimage_path = location,
            precompile_execution_file = workload
        )
    end

    if invocation
        command = "$(Base.julia_cmd().exec[1]) --project=\"$PROJECT\""
        if isfile(location)
            print("$command --sysimage=\"$location\"")
        else
            print(command)
        end
    end
end

run(arguments = ARGS) = main(;
    parse_args(arguments, settings(), as_symbols = true)...
)

end # module
