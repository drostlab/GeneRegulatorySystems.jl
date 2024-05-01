module Script

using ArgParse

settings() = @add_arg_table! ArgParseSettings(
    prog = "export",
    autofix_names = true,
    exit_after_help = false,
) begin
    "location"
        required = true

    "sink"

    "--format", "-x"
        arg_type = Symbol

    "--path", "-p"
        arg_type = String
        action = :append_arg

    "--model", "-m"
        arg_type = String
        action = :append_arg

    "--label", "-l"
        arg_type = Regex
        action = :append_arg

    "--events", "-e"
        arg_type = Regex
        action = :append_arg

    "--kinds", "-k"
        arg_type = Regex
        default = r""

    "--dry"
        action = :store_true
end

function run(arguments = ARGS)
    parsed = @something(
        parse_args(arguments, settings(), as_symbols = true),
        return 1
    )

    @eval import ExportTool
    try Base.invokelatest(ExportTool.main; parsed...)
    catch e
        if e == :help
            ArgParse.show_help(settings(); exit_when_done = false)
            return 1
        else
            rethrow()
        end
    end
end

end

exit(something(Script.run(), 0))
