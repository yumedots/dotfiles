local cfg = (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config"))
local cursor = cfg .. "/hypr/plugins/agent-cursor/agent-cursor.bin"
local borders = cfg .. "/hypr/plugins/borders-plus-plus/borders-plus-plus.so"

-- ecosystem:enforce_permissions is off on this system, so the plugins load without
-- a permission prompt. The rules below keep them working if that ever changes.
hl.permission({ binary = cursor, type = "plugin", mode = "allow" })
hl.plugin.load(cursor)

hl.permission({ binary = borders, type = "plugin", mode = "allow" })
hl.plugin.load(borders)

hl.config({
    plugin = {
        borders_plus_plus = {
            add_borders      = 1,
            border_size_1    = 1,
            natural_rounding = true,
            col              = { border_1 = "rgba(000000ff)" },
        },
    },
})
