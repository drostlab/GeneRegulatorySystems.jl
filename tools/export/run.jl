module Script

using ArgParse

DESCRIPTION = """
Convert the results produced by the experiment tool to wide format (counts
matrices).
"""

EPILOG = """
This will produce a counts matrix with trajectory components as rows, simulation
segments as columns, and values ending the respective segments.
Values that have no events in their segment will be empty (for CSV) or null
(for Arrow).
The rows are named in the first column, and the column names are set according
to the segment's label with its ending time appended.
If these column names are not unique, labels will be dropped and the segment id
will be included.



The segments and trajectory components to include can (and typically need to) be
filtered, for example by selecting only the segments corresponding to extraction
models.
The easiest way to achieve this is to already prepare the simulation schedule
such that it redirects the targeted segments into a separate events stream by
defining `"into"`, and then to filter for that stream using the `--events`
option.
"""

settings() = @add_arg_table! ArgParseSettings(
    prog = "export",
    description = DESCRIPTION,
    epilog = EPILOG,
    autofix_names = true,
    exit_after_help = false,
) begin
    "source"
        required = true
        help = "Set the path to the results location to operate on."

    "sink"
        help = """
            Define where to place the exported results. \
            If not provided, write to standard output.\
        """

    "--format", "-x"
        arg_type = Symbol
        help = """
            Choose the output format: one of `csv`, `tsv` or `arrow`. \
            If missing, it will be determined from the SINK filename \
            extension, falling back to `csv` if SINK is also missing.\
        """

    "--path", "-p"
        arg_type = String
        action = :append_arg
        help = """
            Filter for simulation segments that have a path starting with this \
            prefix.\
        """

    "--model", "-m"
        arg_type = String
        action = :append_arg
        help = """
            Filter for simulation segments that have a model path starting \
            with this prefix.\
        """

    "--label", "-l"
        arg_type = Regex
        action = :append_arg
        help = """
            Filter for simulation segments that have a label matching this \
            regular expression anywhere.\
        """

    "--events", "-e"
        arg_type = Regex
        action = :append_arg
        help = """
            Filter for simulation segments that have a an events stream name \
            matching this regular expression anywhere.\
        """

    "--kinds", "-k"
        arg_type = Regex
        default = r""
        help = """
            Filter for trajectory dimensions that have names matching this \
            regular expression anywhere.\
        """

    "--dry"
        action = :store_true
        help = "Don't export, only pring matching simulation segments."
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
