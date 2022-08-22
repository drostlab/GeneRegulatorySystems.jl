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

resolve(location) = replace(
    location,
    "{SCRATCHSPACE}" => SCRATCHSPACE,
    "{VERSION}" => GeneRegulatorySystemsTools.repository_version(),
)

function settings(; location = nothing)
    default_location = "{SCRATCHSPACE}/{VERSION}.so"
    location = resolve(@something location default_location)
    epilog = """
        sysimage location:
        $(isfile(location) ? "(exists)" : "(does not exist)")
        "$location"
        """

    s = ArgParseSettings(;
        commands_are_required = false,
        epilog,
    )

    @add_arg_table! s begin
        "--location", "-l"
            help = "Where to expect or place the compiled shared object."
            default = default_location

        "compile"
            help = "Compile a new sysimage."
            action = :command

        "invocation"
            help = """
                Write a shell command to standard output that starts Julia with
                the appropriate sysimage.
                """
            action = :command
    end

    @add_arg_table! s["compile"] begin
        "--workload", "-w"
            help = """
                The example execution that determines what to bake into the
                sysimage.
                """
            default = "$(@__DIR__)/precompile_workload.jl"
    end

    s
end

function main(;
    _COMMAND_,
    location,
    invocation = nothing,
    compile = nothing,
)
    resolved_location = resolve(location)

    if _COMMAND_ == :invocation
        command = "$(Base.julia_cmd().exec[1]) --project=\"$PROJECT\""
        if isfile(resolved_location)
            print("$command --sysimage=\"$resolved_location\"")
        else
            print(command)
        end
    elseif _COMMAND_ == :compile
        mkpath(dirname(resolved_location))
        if startswith(location, "{SCRATCHSPACE}/")
            Scratch.track_scratch_access(
                Scratch.find_uuid(GeneRegulatorySystems),
                "sysimages"
            )
        end
        @info "About to compile sysimage" resolved_location Base.julia_cmd()
        @time PackageCompiler.create_sysimage(;
            sysimage_path = resolved_location,
            precompile_execution_file = compile[:workload]
        )
    else
        ArgParse.show_help(settings(; location))
    end
end

run(arguments = ARGS) = main(;
    parse_args(arguments, settings(), as_symbols = true)...
)

end # module
