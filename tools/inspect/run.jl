module Script

using ArgParse

settings() = @add_arg_table! ArgParseSettings(
    prog = "inspect",
    autofix_names = true,
    exit_after_help = false,
) begin
    "location"
        required = true

    "--channel", "-c"

    "--items-prefix", "-i"

    "--label-pattern", "-l"

    "--displays", "-d"
        default = "selector,trajectory,model,legend,info"

    "--kinds", "-k"
        default = "activity,mrnas,proteins"

    "--size", "-s"
        default = "1280x720"

    "--no-wait-for-close"
        action = :store_false
        dest_name = "wait_for_close"
end

function run(arguments = ARGS)
    parsed = @something(
        parse_args(arguments, settings(), as_symbols = true),
        return 1
    )

    @eval import InspectTool
    Base.invokelatest(InspectTool.main; parsed...)
end

end

exit(something(Script.run(), 0))
