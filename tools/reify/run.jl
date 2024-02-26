module Script

using ArgParse

settings() = @add_arg_table! ArgParseSettings(
    prog = "reify",
    autofix_names = true,
    exit_after_help = false,
) begin
    "location"
        required = true

    "path"

    "--representation", "-r"
        action = :store_true

    "--format", "-x"
        arg_type = Symbol
        default = :dump

    "--maxdepth", "-d"
        arg_type = Int
        default = 8
end

function run(arguments = ARGS)
    parsed = @something(
        parse_args(arguments, settings(), as_symbols = true),
        return 1
    )

    @eval import ReifyTool
    Base.invokelatest(ReifyTool.main; parsed...)
end

end

exit(something(Script.run(), 0))
