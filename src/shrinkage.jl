getellipsepoints(radius, lambda) = getellipsepoints(0, 0, radius, lambda)

function getellipsepoints(cx, cy, radius, lambda)
    t = range(0, 2π; length=100)
    ellipse_x_r = cos.(t)
    ellipse_y_r = sin.(t)
    r_ellipse = radius .* hcat(ellipse_x_r, ellipse_y_r) * lambda'
    x = @. cx + r_ellipse[:, 2]
    y = @. cy + r_ellipse[:, 1]
    return x, y
end

function _shrinkage_panel!(ax::Axis, i::Int, j::Int, reref, reest, remat;
                           ellipse::Bool, ellipse_scale::Real, n_ellipse::Integer)
    x, y = view(reref, j, :), view(reref, i, :)
    u, v = view(reest, j, :), view(reest, i, :)
    scatter!(ax, x, y; color=(:red, 0.25))   # reference points
    arrows!(ax, x, y, u .- x, v .- y)        # first so arrow heads don't obscure pts
    plt = scatter!(ax, u, v; color=(:blue, 0.25))  # conditional means at estimates
    if ellipse
        # force computation of current limits
        autolimits!(ax)
        lims = ax.finallimits[]
        cho = remat.λ[[i, j], [j, i]]
        rad_outer = ellipse_scale * mean(lims.widths)
        rad_inner = 0
        for radius in LinRange(rad_inner, rad_outer, n_ellipse + 1)
            ex, ey = getellipsepoints(radius, cho)
            lines!(ax, ex, ey; color=:green, linestyle=:dash)
        end
        # preserve the limits from before the ellipse
        limits!(ax, lims)
    end
    return plt
end

"""
    shrinkageplot!(f::Union{Makie.FigureLike,Makie.GridLayout}, m::MixedModel, gf::Symbol=first(fnames(m)), θref;
                   ellipse=false, ellipse_scale=1, n_ellipse=5)

Return a scatter-plot matrix of the conditional means, b, of the random effects for grouping factor `gf`.

Two sets of conditional means are plotted: those at the estimated parameter values and those at `θref`.
The default `θref` results in `Λ` being a very large multiple of the identity.  The corresponding
conditional means can be regarded as unpenalized.

Correlation ellipses can be added with `ellipse=true`, with the number of ellipses controlled by
`n_ellipse`. The ellipses are equally spaced between the outer ellipse and the origin (center).
The scaling of the ellipses can be adjusted with the multiplicative `ellipse_scale`. If you are
unable to see the ellipses, try increasing `ellipse_scale`.

!!! note
    For degenerate (singular) models, the correlation ellipse will also be degenerate, i.e.,
    collapse to a point or line.
"""
function shrinkageplot!(f::Union{Makie.FigureLike,Makie.GridLayout},
                        m::MixedModel{T},
                        gf::Symbol=first(fnames(m)),
                        θref::AbstractVector{T}=(isa(m, LinearMixedModel) ? 1e4 : 1) .*
                                                m.optsum.initial;
                        ellipse::Bool=false, ellipse_scale::Real=1,
                        n_ellipse::Integer=5) where {T}
    reind = findfirst(==(gf), fnames(m))  # convert the symbol gf to an index
    if isnothing(reind)
        throw(ArgumentError("gf=$gf is not one of the grouping factor names, $(fnames(m))"))
    end
    reest = ranef(m)[reind]          # random effects conditional means at estimated θ
    reref = _ranef(m, θref)[reind]   # same at θref
    remat = m.reterms[reind]

    splomaxes!(f, m.reterms[reind].cnames, _shrinkage_panel!,
               reref, reest, remat; ellipse, ellipse_scale, n_ellipse)

    return f
end

"""
    _ranef(m::MixedModel, θref; uscale::Bool=false)

Compute the conditional modes at θref.

!!! warn
    This function is **not** thread safe because it temporarily mutates
    the passed model before restoring its original form.
"""
function _ranef(m::LinearMixedModel, θref; uscale::Bool=false)
    vv = try
        ranef(updateL!(setθ!(m, θref)))
    catch e
        @error "Failed to compute unshrunken values with the following exception:"
        rethrow(e)
    finally
        updateL!(setθ!(m, m.optsum.final)) # restore parameter estimates and update m
    end
    return vv
end

function _ranef(m::GeneralizedLinearMixedModel, θref; uscale::Bool=false)
    fast = length(m.θ) == length(m.optsum.final)
    setpar! = fast ? MixedModels.setθ! : MixedModels.setβθ!
    vv = try
        ranef(pirls!(setpar!(m, θref), fast, false)) # not verbose
    catch e
        @error "Failed to compute unshrunken values with the following exception:"
        rethrow(e)
    finally
        pirls!(setpar!(m, m.optsum.final), fast, false) # restore parameter estimates and update m
    end

    return vv
end

"""
    shrinkageplot(m::MixedModel, gf::Symbol=first(fnames(m)), θref, args...; kwargs...)

Return a scatter-plot matrix of the conditional means, b, of the random effects for grouping factor `gf`.

Two sets of conditional means are plotted: those at the estimated parameter values and those at `θref`.
The default `θref` results in `Λ` being a very large multiple of the identity.  The corresponding
conditional means can be regarded as unpenalized.

`args...` and `kwargs...` are passed on to [`shrinkageplot!`](@ref)
"""
function shrinkageplot(m::MixedModel, args...; kwargs...)
    f = Figure(; resolution=(1000, 1000)) # use an aspect ratio of 1 for the whole figure

    return shrinkageplot!(f, m, args...; kwargs...)
end
