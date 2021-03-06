# overloadable for other types that might want to offer similar interactions
function interactions end

interactions(ax::Axis) = ax.interactions

"""
    register_interaction!(parent, name::Symbol, interaction)

Register `interaction` with `parent` under the name `name`.
The parent will call `process_interaction(interaction, event, parent)`
whenever suitable events happen.

The interaction can be removed with `deregister_interaction!` or temporarily
toggled with `activate_interaction!` / `deactivate_interaction!`.
"""
function register_interaction!(parent, name::Symbol, interaction)
    haskey(interactions(parent), name) && error("Interaction $name already exists.")
    registration_setup!(parent, interaction)
    push!(interactions(parent), name => (true, interaction))
    return interaction
end

"""
    register_interaction!(interaction::Function, parent, name::Symbol)

Register `interaction` with `parent` under the name `name`.
The parent will call `process_interaction(interaction, event, parent)`
whenever suitable events happen.
This form with the first `Function` argument is especially intended for `do` syntax.

The interaction can be removed with `deregister_interaction!` or temporarily
toggled with `activate_interaction!` / `deactivate_interaction!`.
"""
function register_interaction!(interaction::Function, parent, name::Symbol)
    haskey(interactions(parent), name) && error("Interaction $name already exists.")
    registration_setup!(parent, interaction)
    push!(interactions(parent), name => (true, interaction))
    return interaction
end

"""
    deregister_interaction!(parent, name::Symbol)

Deregister the interaction named `name` registered in `parent`.
"""
function deregister_interaction!(parent, name::Symbol)
    !haskey(interactions(parent), name) && error("Interaction $name does not exist.")
    _, interaction = interactions(parent)[name]

    deregistration_cleanup!(parent, interaction)
    pop!(interactions(parent), name)
    return interaction
end

function registration_setup!(parent, interaction)
    # do nothing in the default case
end

function deregistration_cleanup!(parent, interaction)
    # do nothing in the default case
end

"""
    activate_interaction!(parent, name::Symbol)

Activate the interaction named `name` registered in `parent`.
"""
function activate_interaction!(parent, name::Symbol)
    !haskey(interactions(parent), name) && error("Interaction $name does not exist.")
    interactions(parent)[name] = (true, interactions(parent)[name][2])
    return nothing
end

"""
    deactivate_interaction!(parent, name::Symbol)

Deactivate the interaction named `name` registered in `parent`.
It can be reactivated with `activate_interaction!`.
"""
function deactivate_interaction!(parent, name::Symbol)
    !haskey(interactions(parent), name) && error("Interaction $name does not exist.")
    interactions(parent)[name] = (false, interactions(parent)[name][2])
    return nothing
end


function process_interaction(@nospecialize args...)
    # do nothing in the default case
end

# a generic fallback for functions to have one really simple path to getting interactivity
# without needing to define a special type first
function process_interaction(f::Function, event, parent)
    # in case f is only defined for a specific type of event
    if applicable(f, event, parent)
        f(event, parent)
    end
end



############################################################################
#                            Axis interactions                            #
############################################################################

function _chosen_limits(rz, ax)

    r = positivize(FRect2D(rz.from, rz.to .- rz.from))
    lims = ax.limits[]
    # restrict to y change
    if rz.restrict_x || !ax.xrectzoom[]
        r = FRect2D(lims.origin[1], r.origin[2], widths(lims)[1], widths(r)[2]) 
    end
    # restrict to x change
    if rz.restrict_y || !ax.yrectzoom[]
        r = FRect2D(r.origin[1], lims.origin[2], widths(r)[1], widths(lims)[2]) 
    end
    return r
end

function _selection_vertices(outer, inner)
    _clamp(p, plow, phigh) = Point2f0(clamp(p[1], plow[1], phigh[1]), clamp(p[2], plow[2], phigh[2]))

    outer = positivize(outer)
    inner = positivize(inner)

    obl = bottomleft(outer)
    obr = bottomright(outer)
    otl = topleft(outer)
    otr = topright(outer)

    ibl = _clamp(bottomleft(inner), obl, otr)
    ibr = _clamp(bottomright(inner), obl, otr)
    itl = _clamp(topleft(inner), obl, otr)
    itr = _clamp(topright(inner), obl, otr)

    vertices = [obl, obr, otr, otl, ibl, ibr, itr, itl]
end

function process_interaction(r::RectangleZoom, event::MouseEvent, ax::Axis)

    if event.type === MouseEventTypes.leftdragstart
        r.from = event.prev_data
        r.to = event.data
        r.rectnode[] = _chosen_limits(r, ax)

        selection_vertices = lift(_selection_vertices, ax.limits, r.rectnode)

        # manually specify correct faces for a rectangle with a rectangle hole inside
        faces = [1 2 5; 5 2 6; 2 3 6; 6 3 7; 3 4 7; 7 4 8; 4 1 8; 8 1 5]

        mesh = mesh!(ax.scene, selection_vertices, faces, color = (:black, 0.33), shading = false,
            fxaa = false) # fxaa false seems necessary for correct transparency
        wf = wireframe!(ax.scene, r.rectnode, color = (:black, 0.66), linewidth = 2)
        # translate forward so selection mesh and frame are never behind data
        translate!(mesh, 0, 0, 100)
        translate!(wf, 0, 0, 110)
        append!(r.plots, [mesh, wf])
        r.active = true

    elseif event.type === MouseEventTypes.leftdrag
        r.to = event.data
        r.rectnode[] = _chosen_limits(r, ax)

    elseif event.type === MouseEventTypes.leftdragstop
        newlims = r.rectnode[]
        if !(0 in widths(newlims))
            ax.targetlimits[] = newlims
        end

        while !isempty(r.plots)
            delete!(ax.scene, r.plots[1])
            deleteat!(r.plots, 1)
        end
        # remove any possible links in plotting functions
        empty!(r.rectnode.listeners)
        r.active = false
    end

    return nothing
end

function process_interaction(r::RectangleZoom, event::KeysEvent, ax::Axis)
    r.restrict_y = Keyboard.x in event.keys
    r.restrict_x = Keyboard.y in event.keys
    r.active || return

    r.rectnode[] = _chosen_limits(r, ax)
    return nothing
end


function positivize(r::FRect2D)
    negwidths = r.widths .< 0
    newori = ifelse.(negwidths, r.origin .+ r.widths, r.origin)
    newwidths = ifelse.(negwidths, -r.widths, r.widths)
    FRect2D(newori, newwidths)
end


function process_interaction(l::LimitReset, event::MouseEvent, ax::Axis)

    if event.type === MouseEventTypes.leftclick
        if ispressed(ax.scene, Keyboard.left_control)
            autolimits!(ax)
        end
    end

    return nothing
end


function process_interaction(s::ScrollZoom, event::ScrollEvent, ax::Axis)
    # use vertical zoom
    zoom = event.y

    tlimits = ax.targetlimits
    xzoomlock = ax.xzoomlock
    yzoomlock = ax.yzoomlock
    xzoomkey = ax.xzoomkey
    yzoomkey = ax.yzoomkey

    scene = ax.scene
    e = events(scene)
    cam = camera(scene)

    if zoom != 0
        pa = pixelarea(scene)[]

        # don't let z go negative
        z = max(0.1f0, 1f0 - (abs(zoom) * s.speed))
        if zoom > 0
            z = 1/z   # sets the old to be a fraction of the new. This ensures zoom in & then out returns to original position.
        end

        mp_axscene = Vec4f0((e.mouseposition[] .- pa.origin)..., 0, 1)

        # first to normal -1..1 space
        mp_axfraction =  (cam.pixel_space[] * mp_axscene)[1:2] .*
            # now to 1..-1 if an axis is reversed to correct zoom point
            (-2 .* ((ax.xreversed[], ax.yreversed[])) .+ 1) .*
            # now to 0..1
            0.5 .+ 0.5

        xorigin = tlimits[].origin[1]
        yorigin = tlimits[].origin[2]

        xwidth = tlimits[].widths[1]
        ywidth = tlimits[].widths[2]

        newxwidth = xzoomlock[] ? xwidth : xwidth * z
        newywidth = yzoomlock[] ? ywidth : ywidth * z

        newxorigin = xzoomlock[] ? xorigin : xorigin + mp_axfraction[1] * (xwidth - newxwidth)
        newyorigin = yzoomlock[] ? yorigin : yorigin + mp_axfraction[2] * (ywidth - newywidth)

        timed_ticklabelspace_reset(ax, s.reset_timer, s.prev_xticklabelspace, s.prev_yticklabelspace, s.reset_delay)

        tlimits[] = if ispressed(scene, xzoomkey[])
            FRect(newxorigin, yorigin, newxwidth, ywidth)
        elseif ispressed(scene, yzoomkey[])
            FRect(xorigin, newyorigin, xwidth, newywidth)
        else
            FRect(newxorigin, newyorigin, newxwidth, newywidth)
        end

    end
end

function process_interaction(dp::DragPan, event::MouseEvent, ax)

    if event.type !== MouseEventTypes.rightdrag
        return nothing
    end

    tlimits = ax.targetlimits
    xpanlock = ax.xpanlock
    ypanlock = ax.ypanlock
    xpankey = ax.xpankey
    ypankey = ax.ypankey
    panbutton = ax.panbutton

    scene = ax.scene

    movement = AbstractPlotting.to_world(ax.scene, event.px) .-
               AbstractPlotting.to_world(ax.scene, event.prev_px)

    xori, yori = Vec2f0(tlimits[].origin) .- movement

    if xpanlock[] || ispressed(scene, ypankey[])
        xori = tlimits[].origin[1]
    end

    if ypanlock[] || ispressed(scene, xpankey[])
        yori = tlimits[].origin[2]
    end

    timed_ticklabelspace_reset(ax, dp.reset_timer, dp.prev_xticklabelspace, dp.prev_yticklabelspace, dp.reset_delay)

    tlimits[] = FRect(Vec2f0(xori, yori), widths(tlimits[]))
           
    return nothing
end
