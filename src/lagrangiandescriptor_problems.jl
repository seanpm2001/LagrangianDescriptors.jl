"""
    LagrangianDescriptorProblem

Defines a Lagrangian descriptor problem associated with a SciML differential equations problem.

## Constructor

    LagrangianDescriptorProblem(prob, M, uu0; direction=:both)

`LagrangianDescriptorProblem` can be constructed by passing a differential equation problem (currently only `ODEProblem`, but more problem types will be added), an infinitesimal Lagrangian descriptor with arguments compatible with the differential equation problem, an array of initial conditions, and, optionally, the direction of the flow.

### Arguments

- `prob`: the differential equation problem (e.g. `ODEProblem`, `SDEProblem`, `RODEProblem`, etc.).
- `M`: infinitesimal Lagrangian descriptor (e.g. `M=M(du, u, t, p)` for an ODEProblem).
- `uu0`: collection of initial conditions.
- `direction`: the direction of the flow, with default `:both`, but also accepting `:forward` and `:backward`.

### Fields

With the given arguments, the constructor for `LagrangianDescriptorProblem` returns a type with the following arguments:

- `ensprob::T1`: a suitable ensemble problem to be solved with the given collection of initial conditions `uu0` for each solve, with a suitable `prob_func` to iterate through the collection and a suitable `output_func` to only collect the Lagrangian descriptors at the end of the time interval.
- `uu0::T2`: the given collection of initial conditions.
- `direction::T3`: the given or the default direction of the flow.

## Example Problem

Here we apply the Lagrangian descriptor method to a periodically-forced Duffing equation.

```julia
using OrdinaryDiffEq
using LinearAlgebra: norm
using LagrangianDescriptors

function f!(du, u, p, t)
    x, y = u
    A, ω = p
    du[1] = y
    du[2] = x - x^3 + A * cos(ω * t)
end

u0 = [0.5, 2.2]
tspan = (0.0, 13.0)
A = 0.3; ω = π; p = (A, ω)

prob = ODEProblem(f!, u0, tspan, p)

M(du, u, p, t) = norm(du)

uu0 = [[x, y] for y in range(-1.0, 1.0, length=301), x in range(-1.8, 1.8, length=301)]

lagprob = LagrangianDescriptorProblem(prob, M, uu0)

lagsol = solve(lagprob, Tsit5())

plot(lagsol)
```
"""
struct LagrangianDescriptorProblem{T1,T2,T3}
    ensprob::T1
    uu0::T2
    direction::T3
    method::Symbol

    function LagrangianDescriptorProblem(prob, M, uu0; direction::Symbol = :both, method::Symbol=:augmented, kwargs...)
        ensprob = get_ensemble_problem(prob, M, uu0; direction, method, kwargs...)
        return new{typeof(ensprob),typeof(uu0),typeof(direction)}(ensprob, uu0, direction, method)
    end    
end

function get_ensemble_problem(prob, M, uu0; direction::Symbol=:both, method::Symbol=:augmented, kwargs...)
    if method == :augmented
        return _get_ensemble_problem_augmented(prob, M, uu0; direction, kwargs...)
    elseif method == :postprocessed
        return _get_ensemble_problem_postprocessed(prob, M, uu0; direction, kwargs...)
    else
        throw(
            ArgumentError(
                "Method not implemented"
            )
        )
    end
end

function _get_ensemble_problem_augmented(prob, M, uu0; direction::Symbol=:both, kwargs...)
    if direction == :both
        prob_func = function (augprob, i, repeat; uu0 = uu0)
            remake(
                augprob,
                u0 = ComponentVector(
                    fwd = uu0[i],
                    bwd = uu0[i],
                    lfwd = 0.0,
                    lbwd = 0.0,
                ),
            )
        end
        output_func = function (sol, i)
            (ComponentArray(lfwd = last(sol).lfwd, lbwd = last(sol).lbwd), false)
        end
    elseif direction == :forward
        prob_func = function (augprob, i, repeat; uu0 = uu0)
            remake(augprob, u0 = ComponentVector(fwd = uu0[i], lfwd = 0.0))
        end
        output_func = function (sol, i)
            (ComponentArray(lfwd = last(sol).lfwd), false)
        end
    elseif direction == :backward
        prob_func = function (augprob, i, repeat; uu0 = uu0)
            remake(augprob, u0 = ComponentVector(bwd = uu0[i], lbwd = 0.0))
        end
        output_func = function (sol, i)
            (ComponentArray(lbwd = last(sol).lbwd), false)
        end
    else
        throw(
            ArgumentError(
                "Keyword argument `direction = $direction` not implemented; use either `:forward`, `:backward` or `:both`",
            ),
        )
    end

    augprob = augmentprob(prob, M; direction)
    ensprob = EnsembleProblem(augprob, prob_func = prob_func, output_func = output_func, kwargs...)

   return ensprob
end

function _get_ensemble_problem_postprocessed(prob, M, uu0; direction::Symbol=:both, kwargs...)
    if direction == :both
        prob_func = function (prob, i, repeat; uu0 = uu0)
            isodd(i) ? remake(prob, u0 = uu0[div(i+1,2)], tspan = extrema(prob.tspan)) : remake(prob, tspan = reverse(extrema(prob.tspan)))
        end
        output_func = function (sol, i)
            (lagrangian_descriptor(sol, M), false)
        end
        reduction_func = function (u, batch, I)
            (append!(u, ComponentArray(lfwd = batch[1], lbwd = batch[2])), false)
        end
    elseif direction == :forward
        prob_func = function (prob, i, repeat; uu0 = uu0)
            remake(prob, u0 = uu0[i])
        end
        output_func = function (sol, i)
            (lagrangian_descriptor(sol, M), false)
        end
        reduction_func = function (u, batch, I)
            (append!(u, ComponentArray(lfwd = batch[1])), false)
        end
    elseif direction == :backward
        prob_func = function (prob, i, repeat; uu0 = uu0)
            remake(prob, u0 = uu0[i], tspan = reverse(extrema(prob.tspan)))
        end
        output_func = function (sol, i)
            (lagrangian_descriptor(sol, M), false)
        end
        reduction_func = function (u, batch, I)
            (append!(u, ComponentArray(lbwd = batch[1])), false)
        end
    else
        throw(
            ArgumentError(
                "Keyword argument `direction = $direction` not implemented; use either `:forward`, `:backward` or `:both`",
            ),
        )
    end

    ensprob = EnsembleProblem(prob, prob_func = prob_func, output_func = output_func, reduction = reduction_func, kwargs...)

   return ensprob
end
