module Script

using ArgParse

settings() = @add_arg_table! ArgParseSettings(
    prog = "experiment",
    exit_after_help = false
) begin
    "--location", "-l"
        default = "results/{TIMESTAMP}/"

    "--prepare"
        action = :store_true

    "--seed"
        default = "seed"

    "--simulate"
        action = :store_true

    "--progress"
        default = :bars
        arg_type = Symbol

    "--dry"
        action = :store_true

    "specifications"
        nargs = '*'
        arg_type = String
end

function run(arguments = ARGS)
    parsed = @something(
        parse_args(arguments, settings(), as_symbols = true),
        return 1
    )

    if (
        !parsed[:prepare] &&
        !parsed[:simulate] &&
        isempty(parsed[:specifications])
    )
        ArgParse.show_help(settings(); exit_when_done = false)
        return 0
    end

    @eval import ExperimentTool
    try Base.invokelatest(ExperimentTool.main; parsed...)
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
