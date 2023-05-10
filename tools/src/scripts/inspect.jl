module InspectScript

import ..Common: path
import ..Visualization

using ArgParse
import Arrow
using DataFrames
import JSON
using GeneRegulatorySystems
using GLMakie

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
        default = "promoter,mrnas,proteins"

    "--resolution", "-r"
        default = "1280x720"

    "--no-wait-for-close"
        action = :store_false
        dest_name = "wait_for_close"
end

Base.@kwdef struct AdjacentPrefixes
    parent::String
    next::String
    previous::String
    firstborn::String
end

Base.@kwdef struct PreparedData
    simulations::AbstractDataFrame
    slices::Union{AbstractDataFrame, Nothing}
    model::Union{Models.Model, Nothing}
    kinds::AbstractVector{Symbol}
    groups::AbstractVector{String}
    adjacents::AdjacentPrefixes
end

Base.@kwdef struct Selection
    channel::String = ""
    items_prefix::String = ""
    label_pattern::String = ""
end

function load_specification(location)
    specification_path = path(:specification; prefix = location)
    Specifications.load(
        basename(specification_path);
        loader = target -> JSON.parsefile(
            "$(dirname(specification_path))/$target";
            dicttype = Dict{Symbol, Any}
        ),
    )
end

function load_simulations(location; specification)
    locate_definition(experiment, symbol) = repr(
        "text/plain",
        experiment[Symbol("^$symbol")],
    )
    takes = Dict(
        locate_definition(s, :item) => Simulations.takes(s[:take])
        for s in Specifications.unroll(specification)
    )
    transform(
        path(:simulations; prefix = location) |> Arrow.Table |> DataFrame,
        :item => (item -> getindex.(Ref(takes), item)) => :takes,
        :item => LinearIndices => :i,
    )
end

load_slices(location, channel) = DataFrame(
    Arrow.Table(path(:slices, channel; prefix = location))
)

function reify_model(specification, locator)
    reified = Specifications.reify(
        specification,
        parse(Specifications.Locator, locator),
    )[:model]

    result = Models.Model(reified)

    # TODO: Allow models to describe their link structure and then remove this.
    if result isa Models.SciMLJumpModel
        result = Models.Model(Symbol("vanilla-simple"), reified)
    end

    result
end

function filter(simulations; selection)
    template = Dict(
        :channel => channel -> :channel => ByRow(==(channel)),
        :items_prefix =>
            items_prefix ->
                :item => ByRow(contains(Regex("^@$items_prefix(?=/|\$)"))),
        :label_pattern =>
            label_pattern -> :label => ByRow(contains(Regex(label_pattern))),
    )

    criteria = [
        template[name](getproperty(selection, name))
        for name in propertynames(selection)
        if !isempty(getproperty(selection, name))
    ]

    isempty(criteria) ? simulations : subset(simulations, criteria...)
end

function prepare(simulations; selection, specification, location)
    both = rsplit(selection.items_prefix, '/', limit = 2)
    if length(both) < 2
        parent = ""
        current = both[1]
    else
        parent, current = both
    end

    simulations = filter(
        simulations,
        selection = Selection(
            items_prefix = parent;
            selection.channel,
            selection.label_pattern,
        ),
    )

    remove_prefix(x; prefix) =
        isempty(prefix) ? x : split(x, prefix, limit = 2)[2]

    segment_pattern = r"/[^/]*"
    branches = unique(
        something(match(segment_pattern, tail).match, "")
        for tail in remove_prefix.(simulations.item, prefix = "@$parent")
    )
    branch_index = findfirst(==("/$current"), branches)
    if isnothing(branch_index)
        previous = ""
        next = ""
    else
        previous = branch_index > 1 ? parent * branches[branch_index - 1] : ""
        next = branch_index < length(branches) ?
            parent * branches[branch_index + 1] :
            ""
    end

    simulations = filter(
        simulations,
        selection = Selection(; selection.items_prefix)
    )

    firstborn =
        if isempty(simulations)
            ""
        else
            segment = match(
                segment_pattern,
                remove_prefix(
                    first(simulations.item),
                    prefix = "@$(selection.items_prefix)"
                )
            )
            isnothing(segment) ? "" : selection.items_prefix * segment.match
        end

    adjacents = AdjacentPrefixes(; parent, previous, next, firstborn)

    channels = unique(simulations.channel)
    if length(channels) == 1
        slices = load_slices(location, only(channels))
        slices = subset(slices, :simulation => ByRow(in(simulations.i)))

        transform!(
            slices,
            Cols(endswith("promoter")) .=> ByRow(Bool),
            renamecols = false
        )
        # ^ for now: convert promoter states to `Bool[]`s here...
        # TODO: move this into `ExperimentScript`

        components = Visualization.trajectory_components(names(slices))
        kinds = Visualization.kinds(components)
        groups = Visualization.groups(components)
    else
        slices = nothing
        kinds = Symbol[]
        groups = String[]
    end

    model_locators = unique(simulations.model)
    model =
        if length(model_locators) == 1
            reify_model(specification, only(model_locators))
        else
            nothing
        end

    PreparedData(; simulations, slices, model, kinds, groups, adjacents)
end

function attach_display!(
    figure,
    ::Val{:selector};
    data,
    kinds,
    group_colors,
    selection,
)
    items_prefix =
        isempty(selection[].items_prefix) ? " " : selection[].items_prefix
    label_pattern =
        isempty(selection[].label_pattern) ? " " : selection[].label_pattern

    navigation = Dict{Symbol, Button}()
    for (; name, label) in (
        (name = :parent, label = "↰"),
        (name = :previous, label = "▲"),
        (name = :next, label = "▼"),
        (name = :firstborn, label = "↳"),
    )
        value = getproperty(data.adjacents, name)
        is_active = !isempty(value) || name == :parent && items_prefix != " "
        navigation[name] = Button(
            figure,
            buttoncolor =
                is_active ? RGBf(0.92, 0.92, 0.92) : RGBf(0.97, 0.97, 0.97),
            labelcolor =
                is_active ? RGBf(0.0, 0.0, 0.0) : RGBf(0.7, 0.7, 0.7),
            tellheight = false;
            label,
        )
        is_active && on(navigation[name].clicks) do n
            selection[] = Selection(;
                selection[].channel,
                items_prefix = value,
                selection[].label_pattern,
            )
        end
    end

    items_prefix_textbox = Textbox(
        figure,
        stored_string = items_prefix,
        placeholder = "⟨prefix⟩",
    )
    on(items_prefix_textbox.stored_string) do items_prefix
        selection[] = Selection(;
            selection[].channel,
            items_prefix = strip(items_prefix),
            selection[].label_pattern,
        )
    end

    label_pattern_textbox = Textbox(
        figure,
        stored_string = label_pattern,
        placeholder = "⟨pattern⟩",
    )
    on(label_pattern_textbox.stored_string) do label_pattern
        selection[] = Selection(;
            selection[].channel,
            selection[].items_prefix,
            label_pattern = strip(label_pattern),
        )
    end

    navigation[:previous].height[] = Relative(1)
    navigation[:next].height[] = Relative(1)
    stepper = GridLayout(default_rowgap = 0, tellheight = false)
    stepper[1:2, 1] = [navigation[:previous], navigation[:next]]

    widgets = [
        Label(figure, "prefix:")
        navigation[:parent]
        items_prefix_textbox
        stepper
        navigation[:firstborn]
        Label(figure, "label:")
        label_pattern_textbox
    ]

    selector = GridLayout(default_colgap = 12, tellwidth = false)
    selector[1, 1:length(widgets)] = widgets
    colgap!(selector, 3, 8)
    colgap!(selector, 5, 32)

    selector
end

function attach_display!(
    figure,
    ::Val{:trajectory};
    data,
    kinds,
    group_colors,
    selection,
)
    if isnothing(data.slices)
        Label(
            figure,
            "(too unspecific, channel not unique)",
            tellheight = false,
        )
    elseif isempty(data.slices)
        Label(
            figure,
            "(too specific, no data points left)",
            tellheight = false,
        )
    elseif isempty(kinds)
        Label(
            figure,
            "(no trajectory component kinds selected)",
            tellheight = false,
        )
    else
        Visualization.attach_trajectory!(
            figure;
            data.simulations,
            data.slices,
            kinds,
            group_colors,
        )
    end
end

function attach_display!(
    figure,
    ::Val{:model};
    data,
    kinds,
    group_colors,
    selection,
)
    if isnothing(data.model)
        Label(
            figure,
            "(too unspecific, model not unique)",
            tellheight = false,
        )
    else
        Visualization.attach_model!(figure, data.model; group_colors)
    end
end

function attach_display!(
    figure,
    ::Val{:legend};
    data,
    kinds,
    group_colors,
    selection,
)
    if isempty(data.groups)
        Label(figure, "(too unspecific, groups not unique)")
    else
        Legend(
            figure,
            [
                MarkerElement(
                    marker = :circle,
                    markersize = 32,
                    color = group_colors[group]
                )
                for group in data.groups
            ],
            data.groups,
            orientation = :horizontal,
            tellwidth = false,
            tellheight = true,
        )
    end
end

function attach_display!(
    figure,
    ::Val{:info};
    data,
    kinds,
    group_colors,
    selection,
)
    simulations_count = nrow(data.simulations)
    take_count = sum(length.(data.simulations.takes))
    slice_count = isnothing(data.slices) ? 0 : nrow(data.slices)
    Label(
        figure,
        "$simulations_count simulations," *
            " $take_count takes" *
            (slice_count > 0 ? "" : ", $slice_count slices"),
        tellwidth = false,
    )
end

function build_figure(;
    data::PreparedData,
    displays::AbstractSet{Symbol},
    kinds::AbstractVector{Symbol},
    selection::Observable{Selection},
    resolution::Tuple{Int, Int},
)
    figure = Figure(; resolution)

    group_colors = Visualization.group_colors(data.groups)

    subplots = Dict(
        name => attach_display!(
            figure,
            Val(name);
            data,
            kinds,
            group_colors,
            selection,
        )
        for name in displays
    )

    main_plots = collect(skipmissing((
        get(subplots, :trajectory, missing),
        get(subplots, :model, missing),
    )))
    main_grid = GridLayout(tellheight = false)
    main_grid[1, 1:length(main_plots)] = main_plots

    root_plots = collect(skipmissing((
        get(subplots, :selector, missing),
        main_grid,
        get(subplots, :legend, missing),
        get(subplots, :info, missing),
    )))
    figure[1:length(root_plots), 1] = root_plots

    figure
end

function main(;
    location,
    channel,
    items_prefix,
    label_pattern,
    displays,
    kinds,
    resolution,
    wait_for_close,
)
    selection = Observable(
        Selection(
            channel = something(channel, ""),
            items_prefix = something(items_prefix, ""),
            label_pattern = something(label_pattern, ""),
        )
    )
    displays = Set(Symbol.(split(displays, ',', keepempty = false)))
    kinds = Symbol.(split(kinds, ',', keepempty = false))
    resolution = Tuple(parse.(Int, split(resolution, 'x')))

    specification = load_specification(location)
    simulations = load_simulations(location; specification)

    GLMakie.activate!()
    screen = GLMakie.Screen()

    on(selection) do selected
        data = prepare(
            simulations,
            selection = selected;
            specification,
            location,
        )
        figure = build_figure(; data, displays, kinds, selection, resolution)
        empty!(screen)
        display(screen, figure)
    end

    notify(selection)
    if wait_for_close
        wait(screen)
    else
        close(screen)
    end

    return 0
end

run(arguments = ARGS) = main(;
    @something(
        parse_args(arguments, settings(), as_symbols = true),
        return 1
    )...
)

end # module
