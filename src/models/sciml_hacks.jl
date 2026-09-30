using .ModelingToolkitBase: Symbolics, SymbolicUtils.BasicSymbolic
using .JumpProcesses: SciMLBase

@kwdef struct ConstantStepAffect{N, T}
    species::NTuple{N, Int}
    change::NTuple{N, T}
end

(f!::ConstantStepAffect{N, T})(integrator) where {N, T <: Integer} =
    @inbounds for i in 1:N
        integrator.u[f!.species[i]] += f!.change[i]
    end

function customized_jump_problem(;
    system,
    method,
    bracket_data,
)
    operating_point = ModelingToolkitBase.operating_point_preprocess(
        system,
        # This is only the u0 part; we will initialize these directly on the
        # integrator:
        [s => 0 for s in ModelingToolkitBase.unknowns(system)],
    )
    f, u0, parameters = ModelingToolkitBase.process_SciMLProblem(
        ModelingToolkitBase.EmptySciMLFunction{true},
        system,
        operating_point;
        check_length = false,
        build_initializeprob = false,
        u0_eltype = Int,
    )
    indices = Dict(reverse.(enumerate(ModelingToolkitBase.unknowns(system))))
    jumps = ModelingToolkitBase.jumps(system)
    ModelingToolkitBase.JumpProblem(
        SciMLBase.DiscreteProblem(
            SciMLBase.DiscreteFunction{true, true}(
                SciMLBase.DISCRETE_INPLACE_DEFAULT;
                sys = system,
                initialization_data =
                    get(f.kwargs, :initialization_data, nothing)
            ),
            u0,
            (0, Inf),
            parameters;
            u0_eltype = Int,
        ),
        method,
        JumpProcesses.JumpSet(
            massaction_jumps = ModelingToolkitBase.assemble_maj(
                JumpProcesses.MassActionJump[
                    x
                    for x in jumps
                    if x isa JumpProcesses.MassActionJump
                ],
                indices,
                ModelingToolkitBase.JumpSysMajParamMapper(
                    system,
                    parameters;
                    jseqs = jumps,
                    rateconsttype = Float64,
                )
            ),
            constant_jumps =
                assemble_constant_rate_jumps(system; jumps, indices),
        );
        bracket_data,
        dependencies(method, jumps, indices)...,
        callback = ModelingToolkitBase.process_events(
            system;
            op = operating_point,
            reset_jumps = true,
            tspan = (0.0, Inf),
        ),
        scale_rates = false,
        nocopy = true,
        save_positions = (false, false),
        rng = Random.Xoshiro(),
    )
end

function assemble_constant_rate_jumps(system; jumps, indices)
    normalized_indices = Dict{Symbol, Int}(
        normalize_name(unknown) => i for (unknown, i) in indices
    )
    JumpProcesses.ConstantRateJump[
        #ModelingToolkitBase.assemble_crj(system, jump, nothing)
        JumpProcesses.ConstantRateJump(
            obtain_rate_callable(system, jump),
            obtain_affect(jump; normalized_indices)
        )
        for jump in jumps
        if jump isa JumpProcesses.ConstantRateJump
    ]
end

function obtain_rate_callable(system, jump)
    T = Tuple{2, 3, ModelingToolkitBase.is_split(system)}
    ModelingToolkitBase.GeneratedFunctionWrapper{T}(
        ModelingToolkitBase.eval_or_rgf(
            # ^ Defaults to `eval_expression = false`, i.e. using a
            # RuntimeGeneratedFunction
            ModelingToolkitBase.generate_rate_function(system, jump.rate),
        ),
        nothing,
    )
end

obtain_affect(jump; normalized_indices) =
    ConstantStepAffect(
        Tuple(
            normalized_indices[normalize_name(Symbolics.value(affect.lhs))]
            for affect in jump.affect!
        ),
        Tuple(stoichiometry.(jump.affect!)),
    )

function stoichiometry(affect::ModelingToolkitBase.Equation)
    value = ModelingToolkitBase.value
    Pre = ModelingToolkitBase.Pre
    expand = Symbolics.expand
    substitute = Symbolics.substitute
    change = value(expand(substitute(
        value(affect.rhs),
        Dict(Pre(value(affect.lhs)) => 0),
    )))
    change isa Number || error(
        "affect `$(affect)` does not change its species by a constant amount"
    )
    Int8(change)
end

function dependencies(method, jumps, indices)
    needs_maps = JumpProcesses.needs_vartojumps_map(method)
    needs_graph = JumpProcesses.needs_depgraph(method)
    needs_maps || needs_graph || return (;)
    forward = ModelingToolkitBase.asgraph(triggers.(jumps; indices), indices)
    backward = variable_dependencies(affected.(jumps; indices), indices)
    graph = needs_graph ?
        ModelingToolkitBase.eqeq_dependencies(forward, backward).fadjlist :
        nothing
    (;
        vartojumps_map = forward.badjlist,
        jumptovars_map = backward.badjlist,
        dep_graph = graph,
    )
end

drop_unindexed!(xs; indices) = filter!(in(keys(indices)) ∘ Symbolics.value, xs)

function triggers(jump; indices)
    result = Set{BasicSymbolic}()
    Symbolics.get_variables!(result, jump.rate)  # returns nothing :/
    drop_unindexed!(result; indices)
    result
end

function triggers(jump::JumpProcesses.MassActionJump; indices)
    result = Set{BasicSymbolic}()
    #= TODO ^ this is supposed to opt into an "optimized" path via
        search_variables!(::AbstractSet{BasicSymbolic}) -- check if this
        actually happens and whether it really is faster, else this code could
        be simplified. =#
    rates = Symbolics.value(jump.scaled_rates)
    rates isa Number || Symbolics.get_variables!(result, rates)
    union!(result, first.(jump.reactant_stoch))
    drop_unindexed!(result; indices)
end

affected(jump; indices) =
    drop_unindexed!([f!.lhs for f! in jump.affect!]; indices)

affected(jump::JumpProcesses.MassActionJump; indices) =
    drop_unindexed!([v for (v, _) in jump.net_stoch]; indices)

function variable_dependencies(affected, indices)
    backwards = map(affected) do variables
        map(variables) do v
            indices[Symbolics.value(v)]
        end |> sort! |> unique!
    end

    forwards = [Int[] for _ in indices]
    for (i, variables) in enumerate(backwards)
        for variable in variables
            push!(forwards[variable], i)
        end
    end

    ModelingToolkitBase.BipartiteGraph(forwards, backwards)
end
