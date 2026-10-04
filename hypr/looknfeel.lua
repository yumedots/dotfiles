hl.config({
    general = {
        gaps_in  = 4,
        gaps_out = 8,

        border_size = 1,

        col = {
            active_border   = "rgba(ffffffee)",
            inactive_border = "rgba(595959aa)",
        },

        resize_on_border = true,

        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 0,
        rounding_power = 0,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = false,
        },

        blur = {
            enabled   = false,
        },

        dim_special = 0.5,
    },

    animations = {
        enabled = true,
    },

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo   = false,
    },

    render = {
        new_render_scheduling = true,
    },
})

hl.curve("quick", { type = "bezier", points = { {0.15, 0}, {0.1, 1} } })

hl.animation({ leaf = "global",        enabled = true, speed = 1.5, bezier = "quick" })
hl.animation({ leaf = "border",        enabled = true, speed = 1.5, bezier = "quick" })
hl.animation({ leaf = "windows",       enabled = true, speed = 2,   bezier = "quick" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 1.6, bezier = "quick", style = "popin 97%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.2, bezier = "quick", style = "popin 97%" })
hl.animation({ leaf = "fade",          enabled = true, speed = 1.5, bezier = "quick" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.2, bezier = "quick" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1,   bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 1.5, bezier = "quick" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 1.5, bezier = "quick", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.2, bezier = "quick", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.2, bezier = "quick" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1,   bezier = "quick" })
hl.animation({ leaf = "workspaces",    enabled = false })
hl.animation({ leaf = "workspacesIn",  enabled = false })
hl.animation({ leaf = "workspacesOut", enabled = false })
