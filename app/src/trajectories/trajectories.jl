module Trajectories

using WGLMakie
import Bonito
using GeneRegulatorySystems: Models, Scheduling
using GeneRegulatorySystems.Visualisation:
    Catenation,
    Series,
    CountSeries,
    FractionSeries,
    Dimension,
    branch, by_kind, cut, place!, seriestype
import GeneRegulatorySystems.Visualisation: describe
import Colors
using Statistics: mean, std, var
using MultivariateStats: PCA, fit, predict
import UMAP

include("sink.jl")
include("lod.jl")
include("render.jl")
include("phase.jl")
include("distributions.jl")

# TODO: add this upstream to Makie
function dismiss_on_leave(figure)
    on(events(figure).entered_window) do inside
        inspector = figure.scene.data_inspector
        inside || isnothing(inspector) || (inspector.plot.visible[] = false)
    end
end

function unsubscribe!(scene)
    foreach(off, scene.deregister_callbacks)
    empty!(scene.deregister_callbacks)
    foreach(unsubscribe!, scene.children)
end

embed(render, theme::Theme, children...) = Bonito.App() do
    with_theme(theme; Lines = (; linecap = :round, joinstyle = :round)) do
        figure = render()
        entered = events(figure).entered_window
        dismiss_on_leave(figure)
        on(events(figure).window_open) do open
            open || unsubscribe!(figure.scene)
        end
        container = Bonito.DOM.div(
            WGLMakie.WithConfig(figure; resize_to = (:parent, nothing)),
            children...;
            style = "width: 100%; height: 100%;",
        )
        Bonito.DOM.div(
            container,
            Bonito.js"""
                const container = $(container)
                container.addEventListener("mouseenter", () => $(entered).notify(true))
                container.addEventListener("mouseleave", () => $(entered).notify(false))
            """;
            style = "width: 100%; height: 100%;",
        )
    end
end

end
