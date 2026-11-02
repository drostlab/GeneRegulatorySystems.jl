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

embed(render, theme::Theme, children...) = Bonito.App() do
    with_theme(theme) do
        Bonito.DOM.div(
            WGLMakie.WithConfig(render(); resize_to = (:parent, nothing)),
            children...;
            style = "width: 100%; height: 100%;",
        )
    end
end

end
