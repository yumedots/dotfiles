-- drop-preview: shows where a dragged tiled window will land.
-- Only active while a mouse button is held (mouse drags, not touch/tablet).

local cfg  = (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config"))
local path = cfg .. "/hypr/plugins/drop-preview/drop-preview.so"

hl.permission({ binary = path, type = "plugin", mode = "allow" })
hl.plugin.load(path)

hl.config({
    plugin = {
        drop_preview = {
            enabled = true,

            -- gray border, dark translucent inside
            col = {
                border = "rgba(909090ff)",
                fill   = "rgba(20202066)",
            },

            -- -1 = follow general:border_size / decoration:rounding
            border_size = -1,
            rounding    = -1,

            spacing = 8, -- inset from the drop area, logical px

            blur            = false, -- blur behind the fill
            animation_speed = 0,     -- 0 = snap instantly, higher = smoother slide
            generic_fallback = true, -- master/scrolling/monocle: highlight hovered window
        },
    },
})
