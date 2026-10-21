local suppressMaximizeRule = hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.layer_rule({
    name  = "static-shell-layers",
    match = { namespace = "^(tooltip|launcher)$" },

    no_anim = true,
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- The agent window opens at the size of its content, floating, so it can be
-- moved and resized like any other window.
hl.window_rule({
    name  = "agent-window",
    match = { class = "org.quickshell", title = "^Agent$" },

    size  = "320 620",
    float = true,
})
