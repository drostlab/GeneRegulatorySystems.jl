module SysimageScript

import GeneRegulatorySystemsTools

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
        prog = "sysimage",
        commands_are_required = false,
        exit_after_help = false,
        epilog,
    )

    @add_arg_table! s begin
        "--location", "-l"
            help = "Where to expect or place the custom sysimage."
            default = default_location

        "compile"
            help = "Compile a new custom sysimage."
            action = :command

        "locate"
            help = """
                If it exists, write the location of the custom sysimage to
                standard output, otherwise the location of the default
                sysimage.
                """
            action = :command

        "delete"
            help = "Delete the custom sysimage, if it exists."
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
    compile = nothing,
    locate = nothing,
    delete = nothing,
)
    resolved_location = resolve(location)

    if _COMMAND_ == :locate
        if isfile(resolved_location)
            resolved_location
        else
            unsafe_string(Base.JLOptions().image_file)
        end |> print
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
    elseif _COMMAND_ == :delete
        if isfile(resolved_location)
            rm(resolved_location)
        end
    else
        ArgParse.show_help(settings(; location), exit_when_done = false)
    end
end

run(arguments = ARGS) = main(;
    @something(
        parse_args(arguments, settings(), as_symbols = true),
        return
    )...
)

end # module
