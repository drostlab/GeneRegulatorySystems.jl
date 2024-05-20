module Script

using ArgParse

DESCRIPTION = """
Recreate an object from a simulation schedule, identified by its path, and
describe it to standard output.
"""

EPILOG = """
This tool can be used to explore the semantics of the scheduling mechanism, or
to obtain a concrete model specification that is otherwise available only
indirectly where models are specified from templates.



The format of the target path is described in detail the main documentation,
but briefly, it starts with a component identifying the scope within the
schedule (which may correspond to an individual simulation segment) and can
optionally be suffixed by additional `.`-separated components allowing to index
further into the identified object.
Generally, given a results location as produced by the experiment tool, all
values in the `path` and `model` columns in its index, as well as their
prefixes, are valid targets for reification.



Omitting the object path identifies the root `Schedule`.
If an identified object is a `Schedule`: appending a `+` expands definitions if
its specification is a `Scope`; appending a `-` or `/` and then an integer
descends into the respective iteration if its specification is a `Sequence`; and
appending a `.` followed by a name accesses the corresponding binding.
If an identified object is a `Primitive`, appending a `+` accesses the wrapped
model.
Otherwise, appending a `.` followed by a name accesses the identified object's
property by name, and appending a `.` followed by an integer indexes into a
vector.
"""

settings() = @add_arg_table! ArgParseSettings(
    prog = "reify",
    description = DESCRIPTION,
    epilog = EPILOG,
    autofix_names = true,
    exit_after_help = false,
) begin
    "location"
        required = true
        help = """
            Set the schedule to operate on, either as a results location as \
            produced by the experiment tool or as the filesystem path to a \
            schedule file.\
        """

    "path"
        help = """
            Set the path identifying, within the schedule, the object to be
            reified. \
            See more info below.\
        """

    "--representation", "-r"
        action = :store_true
        help = """
            Before output, transform the identified object to a structured \
            representation that is equivalent to how it could have been \
            defined in the scheduling language. \
            This is currently only defined for special cases and fails \
            with an error otherwise.\
        """

    "--format", "-x"
        arg_type = Symbol
        default = :tree
        help = """
            Specify how to format the result: \
            with `--format=dump`, print it using Julia's `dump` function; \
            with `--format=julia`, print its Julia `repr`; \
            with `--format=json`, output a JSON serialization; \
            with `--format=tree`, pretty-print it as a tree. \
            JSON output typically requires `--representation` as well.\
        """

    "--maxdepth", "-d"
        arg_type = Int
        default = 8
        help = """
            Specify the depth to descend to when `--format=dump` or \
            `--format=tree` is used.\
        """
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
