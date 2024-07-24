# Getting started

## CLI setup

With [Git](https://git-scm.com/) installed, the easiest way to get started using the command line interface is to clone this repository, e.g. like
```sh
git clone https://github.com/lmshk/GeneRegulatorySystems.jl $HOME/src/grs
```
and then run the utilities via the (currently Unix-only) wrapper script. From the cloned directory, run
```sh
tools/grs
```
to see the included utilities.

!!! compat
    This assumes that a recent Julia is available as `julia`; you may alternatively override the used Julia binary by setting the `JULIA` environment variable, for example by prepending it like
    ```sh
    JULIA=/path/to/julia tools/grs
    ```
    for a single invocation.

The wrapper will automatically run the utilities in individual Julia environments with their respective dependencies, which may take a couple of minutes on each first use as they are precompiled.

!!! tip
    For convenience, you could optionally create a shortcut to `tools/grs`, for example by defining an `alias` in your `.bashrc` like
    ```sh
    echo "alias grs='\$HOME/src/grs/tools/grs'" >> "$HOME/.bashrc"
    ```
    or by adding `$HOME/src/grs/tools` to your `PATH` environment variable.

!!! compat
    On Windows, since the wrapper is not available you need to run the tools manually by setting the correct Julia environment. For example, you can run
    ```sh
    julia --project=tools/experiment tools/experiment/run.jl
    ```
    from the cloned directory.

To update the toolset, simply check out a new version using Git. For example, run
```sh
git pull
```
from within the repository directory chosen above. The `tools/grs` wrapper script will automatically re-instantiate the changed tools' environments on first use.

## Quickstart

Simulation experiments are specified by schedules that define the models to be simulated and how their time evolution should be concatenated along the time dimension. These schedules may be assembled manually or loaded from specification files written in a JSON-based mini-language. See the `examples` directory for a collection of example schedules, and also the [Scheduling](@ref) reference documentation.

The following assumes that you have made the `tools/grs` wrapper script available as `grs` as described above. From the repository's directory, run
```sh
grs experiment examples/toy/repressilator.schedule.json
```
to run that schedule. Outputs are by default placed in a `results` subdirectory of the current working directory, which can be changed using the `--location` argument when invoking `grs experiment`. Run `grs experiment --help` for more options, and see [`experiment` tool](@ref) for details.

The results consist of
* the schedule(s) that were run to produce them (listed in `experiment.schedule.json`),
* the simulated event stream(s) (ending in `.stream.arrow`) in long format and
* the index of all executed simulation segments (`index.arrow`).

You can inspect Arrow files e.g. like
```julia
using DataFrames
import Arrow

DataFrame(Arrow.Table("path/to/results/index.arrow"))
```
both for the streaming and non-streaming variant. See [Results format](@ref) for details.

There is an experimental Makie.jl-based `grs inspect` tool that can display the results and supports some interactivity. Run it like
```sh
grs inspect path/to/results/
```
and see [`inspect` tool](@ref) for details.

You can export results from their native (long) format to a wide format using the `grs export` tool. Its default behavior is to include the values of all trajectory dimensions at the end of each simulation segment, although both the included dimensions and considered segments can be pre-filtered; see [`export` tool](@ref) for details.
