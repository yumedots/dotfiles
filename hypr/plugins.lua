local cfg = (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config"))
local plugin = cfg .. "/hypr/plugins/agent-cursor/agent-cursor.bin"

-- ecosystem:enforce_permissions is off on this system, so the plugin loads without
-- a permission prompt. The rule below keeps it working if that ever changes.
hl.permission({ binary = plugin, type = "plugin", mode = "allow" })
hl.plugin.load(plugin)
