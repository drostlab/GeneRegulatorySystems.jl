module Visualization

import Colors: Colors, @colorant_str
using DataFrames
using Makie
import GeneRegulatorySystems
import Graphs
import GraphMakie

COMPONENT_PATTERN = r"(?<group>.+)\.(?<kind>.+)"

struct TrajectoryComponent
    kind::Symbol
    group::String
end

trajectory_components(names::AbstractVector{<:AbstractString}) = [
    TrajectoryComponent(Symbol(m[:kind]), m[:group])
    for m in match.(COMPONENT_PATTERN, names)
    if !isnothing(m)
]

kinds(components::AbstractVector{TrajectoryComponent}) =
    unique(getproperty.(components, :kind))

groups(components::AbstractVector{TrajectoryComponent}) =
    unique(getproperty.(components, :group))

group_colors(
    groups;
    seed = [colorant"white", colorant"black", colorant"crimson"]
) = Dict(
    zip(
        groups,
        Colors.distinguishable_colors(
            length(groups),
            seed,
            dropseed = true
        )
    )
)

# TODO: clean this up
kindname(kind::Symbol) = kindname(Val(kind))
kindname(::Val{Kind}) where {Kind} = replace(String(Kind), '_' => ' ')
kindname(::Val{:promoters}) = "promoter states"
kindname(::Val{:mrnas}) = "mRNAs"
kindname(::Val{:premrnas}) = "pre-mRNAs"

function attach_trajectory_label!(figure; kind, yscale)
    label = Label(
        figure,
        kindname(kind),
        rotation = π / 2,
        tellheight = false,
    )

    mouseevents = addmouseevents!(
        label.blockscene,
        label.layoutobservables.computedbbox,
    )
    onmouseleftdown(mouseevents) do _
        yscale[] = yscale[] == log10 ? identity : log10
    end

    label
end

function attach_trajectory_components!(
    figure,
    ::Type{<:Number};
    simulations,
    slices,
    kind,
    group_colors,
    yscale,
)
    components_of_kind = select(
        slices,
        Cols(endswith(String(kind))),
        copycols = false
    )

    axis = Axis(
        figure,
        xticklabelsvisible = false,
        limits = (
            0.0,
            maximum(slices.t),
            0.5,
            max(1.0, components_of_kind |> eachcol .|> maximum |> maximum),
        );
        yscale
    )

    component_groups = groups(trajectory_components(names(slices)))
    for simulation in eachrow(simulations)
        for take in simulation.takes
            taken_slices = subset(
                slices,
                [:simulation, :t] => (s, t) ->
                    take.from .<= t .<= take.to .&& s .== simulation.i
            )
            if take.step > 0.0 || take.event_resolution > 1
                for group in component_groups
                    scatterlines!(
                        axis,
                        taken_slices.t,
                        taken_slices[!, "$group.$kind"],
                        color = group_colors[group],
                        markersize = 3,
                        linewidth = 1,
                        linestyle = :dash,
                    )
                end
            else
                for group in component_groups
                    stairs!(
                        axis,
                        taken_slices.t,
                        taken_slices[!, "$group.$kind"],
                        color = group_colors[group],
                        step = :pre,
                        linewidth = 1,
                    )
                end
            end
        end
    end

    axis
end

function activation_windows(ts, states)
    ons = Float64[]
    offs = Float64[]

    activation = NaN
    for (t, state) in zip(ts, states)
        if isfinite(activation)
            if iszero(state)
                push!(ons, activation)
                push!(offs, t)
                activation = NaN
            end
        else
            if !iszero(state)
                activation = t
            end
        end
    end

    if isfinite(activation)
        push!(ons, activation)
        push!(offs, ts[end])
    end

    ons, offs
end

function attach_trajectory_components!(
    figure,
    ::Type{Bool};
    simulations,
    slices,
    kind,
    group_colors,
    yscale,
)
    axis = Axis(
        figure;
        xticklabelsvisible = false,
        yticksvisible = false,
        yticklabelsvisible = false,
        yreversed = true,
        limits = (0.0, maximum(slices.t), nothing, nothing),
        tellheight = false,
    )

    component_groups = groups(trajectory_components(names(slices)))
    for (i, simulation) in enumerate(eachrow(simulations))
        for take in simulation.takes
            taken_slices = subset(
                slices,
                [:simulation, :t] => (s, t) ->
                    take.from .<= t .<= take.to .&& s .== simulation.i
            )
            if iszero(take.step) && take.event_resolution == 1
                for (j, group) in enumerate(component_groups)
                    ons, offs = activation_windows(
                        taken_slices.t,
                        taken_slices[!, "$group.$kind"]
                    )
                    position = (j - 1) * nrow(simulations) + (i - 1)
                    barplot!(
                        axis,
                        fill(position, length(offs)),
                        offs;
                        fillto = ons,
                        direction = :x,
                        color = group_colors[group]
                    )
                end
            end
        end
    end

    axis
end

attach_trajectory_components!(figure; slices, kind, rest...) =
    attach_trajectory_components!(
        figure,
        promote_type(
            describe(slices, cols = Cols(endswith("$kind"))).eltype...
        );
        slices,
        kind,
        rest...,
    )

function attach_trajectory!(figure; simulations, slices, kinds, group_colors)
    grid = GridLayout(tellheight = false)

    transform_pattern = r"""
        (?<transform>[[:word:]]+)? (?(transform)\(|)
            (?<kind>.+)
        (?(transform)\)|)
    """x
    for (i, kind) in enumerate(kinds)
        m = match(transform_pattern, String(kind))
        kind = Symbol(m[:kind])
        yscale = Observable{Function}(
            isnothing(m[:transform]) ? identity : log10
        )
        # ^ for now, every non-empty transform is interpreted to mean `log10`
        # TODO: clean this up

        grid[i, 1] = attach_trajectory_label!(figure; kind, yscale)
        grid[i, 2] = attach_trajectory_components!(
            figure;
            simulations,
            slices,
            kind,
            group_colors,
            yscale,
        )
    end
    bottom = content(grid[end, 2])
    bottom.xlabel = "τ"
    bottom.xticklabelsvisible = true

    linkxaxes!(contents(grid[:, 2])...)

    grid
end

function attach_model!(
    figure,
    model::GeneRegulatorySystems.Models.Vanilla.Model;
    group_colors,
)
    axis = Axis(figure, autolimitaspect = 1)

    kinds = [
        :activation => (color = :black, linestyle = :solid),
        :repression => (color = :red, linestyle = :dash),
    ]

    links = Dict(
        (model.genes_index[regulator.from] => model.genes_index[gene.name]) =>
            (; label = repr(regulator.at), style...)
        for gene in model.definition.genes
        for (kind, style) in kinds
        for regulator in getfield(gene, kind).slots
    )

    graph = Graphs.DiGraph(length(model.definition.genes))
    Graphs.add_edge!.(Ref(graph), keys(links))

    # TODO: handle parallel edges?

    link_properties(property) = [
        getproperty(links[Graphs.src(edge) => Graphs.dst(edge)], property)
        for edge in Graphs.edges(graph)
    ]

    edge_attributes = Graphs.ne(graph) == 0 ? (;) : (
        elabels = link_properties(:label),
        elabels_color = link_properties(:color),
        elabels_distance = 24,
        elabels_fontsize = 12,
        edge_plottype = :beziersegments,
        edge_attr = (
            linestyle = link_properties(:linestyle),
            color = link_properties(:color),
        ),
        arrow_attr = (
            size = 16,
            color = link_properties(:color),
        ),
    )

    GraphMakie.graphplot!(
        axis,
        graph,
        node_size = 16,
        node_color = [
            get(group_colors, string(model.definition.genes[i].name), :gray)
            for i in Graphs.vertices(graph)
        ];
        edge_attributes...
    )

    hidespines!(axis)
    hidedecorations!(axis)

    axis
end

end # module
