module InspectTool

include("$(@__DIR__)/../../common.jl")
include("$(@__DIR__)/visualization.jl")

using .Common: TrajectoryComponent

import Arrow
using Chain
using DataFrames
using GeneRegulatorySystems
using GLMakie
using PrecompileTools

@kwdef struct AdjacentPrefixes
    parent::String
    next::String
    previous::String
    firstborn::String
end

@kwdef struct PreparedData
    index::DataFrame
    dimensions::Union{
        Dict{Symbol, Dict{Int, Dict{String, Visualization.Series}}},
        Nothing,
    }
    model::Union{Models.Description, Nothing}
    groups::Union{Vector{String}, Nothing}
    group_colors::Visualization.GroupColors
    adjacents::AdjacentPrefixes
end

@kwdef struct Selection
    channel::String = ""
    items_prefix::String = ""
    label_pattern::String = ""
end

const BRANCH_PATTERN = r"^(?:.*/\d+)?"

branch(path) = match(BRANCH_PATTERN, path).match

function arrange(index)
    result = Int[]
    track = 0
    tracks = Dict{String, Int}()
    watermarks = [0.0]
    for segment in eachrow(index)
        if segment.branch != branch
            track = get!(tracks, segment.branch) do
                if track > 0
                    watermarks[track] = Inf
                end
                @something(
                    findfirst(≤(segment.from), watermarks),
                    lastindex(push!(watermarks, NaN)),
                )
            end
        end
        watermarks[track] = segment.to
        push!(result, track)
    end
    result
end

function filter(index; selection)
    template = Dict(
        :channel => channel -> :into => ByRow(contains(channel)),
        :items_prefix => prefix -> (
            :path => ByRow(contains(Regex("^\\Q$prefix\\E(?=[/+-]|\$)")))
        ),
        :label_pattern =>
            label_pattern -> :label => ByRow(contains(Regex(label_pattern))),
    )

    criteria = [
        template[name](getproperty(selection, name))
        for name in propertynames(selection)
        if !isempty(getproperty(selection, name))
    ]

    subset(index, :count => ByRow(>(0)), criteria...)
end

function load_dimensions(filtered; location)
    sum(filtered.count) < 100_000_000 || return

    result = Dict{Symbol, Dict{Int, Dict{String, Visualization.Series}}}()

    segment_ids = Dict(zip(filtered.i, LinearIndices(eachrow(filtered))))
    components = Dict{Symbol, TrajectoryComponent}()
    for channel in unique(subset(filtered, :count => ByRow(>(0))).into)
        events = @chain begin
            Common.artifact(:events, channel, prefix = location)
            Arrow.Table
            DataFrame
        end

        for event in eachrow(events)
            haskey(segment_ids, event.i) || continue
            component = get!(components, event.name) do
                TrajectoryComponent(event.name)
            end
            series = @chain result begin
                get!(valtype(_), _, component.kind)
                get!(valtype(_), _, segment_ids[event.i])
                get!(_, component.group) do
                    Visualization.Series(component.kind)
                end
            end
            push!(series.ts, event.t)
            push!(series.ys, event.value)
        end
    end

    result
end

function backlinks(index)
    result = Int[]
    tips = [0]
    for segment in eachrow(index)
        local tip, branch
        while true
            tip = last(tips)
            branch = iszero(tip) ? "" : index[tip, :branch]
            startswith(segment.branch, branch) && break
            pop!(tips)
        end
        push!(result, tip)
        segment.branch == branch || push!(tips, tip)
        tips[end] = rownumber(segment)
    end
    result
end

function prepare(index; selection, location)
    parent, current = let
        m = match(r"(.*)(\+|[/-]\d+)$", selection.items_prefix)
        m === nothing ? ["", ""] : m
    end

    index = filter(
        index,
        selection = Selection(
            items_prefix = parent;
            selection.channel,
            selection.label_pattern,
        ),
    )

    segment_pattern = r"^(\+|[/-]?\d+).*"
    siblings = unique(
        match(segment_pattern, chopprefix(path, parent))[1]
        for path in index.path
    )
    previous, next = let
        n = length(siblings)
        i = findfirst(==(current), siblings)
        if n < 2 || i === nothing
            "", ""
        else
            (
                parent * siblings[mod1(i - 1, n)],
                parent * siblings[mod1(i + 1, n)],
            )
        end
    end

    index = filter(index, selection = Selection(; selection.items_prefix))
    index.previous = backlinks(index)

    firstborn =
        if isempty(index)
            ""
        else
            prefix = selection.items_prefix
            first_tail = chopprefix(first(index.path), prefix)
            m = match(segment_pattern, first_tail)
            m === nothing ? "" : prefix * m[1]
        end

    adjacents = AdjacentPrefixes(; previous, next, firstborn, parent)

    dimensions = load_dimensions(index; location)
    if dimensions === nothing
        groups = nothing
    else
        groups = unique(
            group
            for segments in values(dimensions)
            for segment in values(segments)
            for group in keys(segment)
        )
        if length(groups) > 32
            groups = nothing
        end
    end

    group_colors = Visualization.GroupColors(groups)

    model_locators = unique(subset(index, [:from, :to] => ByRow(<)).model)
    model =
        if length(model_locators) == 1
            Models.describe(Common.reify(only(model_locators); location))
        else
            nothing
        end

    PreparedData(;
        index,
        dimensions,
        groups,
        group_colors,
        model,
        adjacents,
    )
end

function attach_display!(figure, ::Val{:selector}; data, selection, _...)
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

function attach_display!(figure, ::Val{:trajectory}; data, kinds, _...)
    if data.dimensions === nothing
        Label(figure, "(≥1000000 slices)", tellheight = false)
    elseif isempty(data.dimensions)
        Label(figure, "(no data)", tellheight = false)
    elseif isempty(kinds)
        Label(figure, "(no kinds selected for display)", tellheight = false)
    else
        Visualization.attach_trajectory!(
            figure;
            data.index,
            data.dimensions,
            kinds,
            data.group_colors,
        )
    end
end

function attach_display!(figure, ::Val{:model}; data, _...)
    if data.model === nothing
        Label(
            figure,
            "(model not unique among non-instant segments)",
            tellheight = false,
        )
    else
        Visualization.attach_model!(figure, data.model; data.group_colors)
    end
end

function attach_display!(figure, ::Val{:legend}; data, _...)
    if data.groups === nothing
        Label(figure, "(>32 groups)")
    else
        Legend(
            figure,
            [
                MarkerElement(
                    marker = :circle,
                    markersize = 32,
                    color = data.group_colors[group],
                )
                for group in sort(data.groups)
            ],
            data.groups,
            orientation = :horizontal,
            tellwidth = false,
            tellheight = true,
        )
    end
end

function attach_display!(figure, ::Val{:info}; data, _...)
    events_count = sum(data.index.count)
    message =
        if data.dimensions === nothing
            "$events_count events (≥100000000, not loaded)"
        else
            groups_count =
                if data.groups === nothing
                    ">32"
                else
                    "$(length(data.groups))"
                end
            "$events_count events of $(length(data.dimensions)) kinds \
                in $groups_count groups × $(nrow(data.index)) segments"
        end
    Label(figure, message, tellwidth = false)
end

function build_figure(;
    data::PreparedData,
    displays::AbstractSet{Symbol},
    kinds::AbstractVector{Symbol},
    selection::Observable{Selection},
    size::Tuple{Int, Int},
)
    figure = Figure(; size)
    subplots = Dict(
        name => attach_display!(
            figure,
            Val(name);
            data,
            kinds,
            data.group_colors,
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
    size,
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
    size = Tuple(parse.(Int, split(size, 'x')))

    index = @chain begin
        Common.artifact(:index; prefix = location)
        Arrow.Table
        DataFrame
    end
    index.branch = branch.(index.path)
    index.track = arrange(index)

    GLMakie.activate!()
    screen = GLMakie.Screen()

    on(selection) do selected
        empty!(screen)
        data = prepare(index, selection = selected; location)
        figure = build_figure(; data, displays, kinds, selection, size)
        display(screen, figure)
    end

    notify(selection)
    if wait_for_close
        wait(screen)
    else
        close(screen)
    end
end

#=
@setup_workload begin
    mktempdir() do location
        # TODO create dummy data
        @compile_workload begin
            # TODO run main
        end
    end
end
=#

end
