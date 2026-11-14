require("monitors")
require("programs")
require("actions")
require("envs")
require("looknfeel")
require("layouts")
require("input")
require("binds")
require("rules")
require("autostart")

local state = (os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/yudae/loaded.lua"
local loaded = io.open(state, "r")

if loaded then
    loaded:close()
    dofile(state)
end
