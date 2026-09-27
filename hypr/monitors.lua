local path = (os.getenv("HOME") or "") .. "/.config/quickshell/cache/display.lua"

local ok, saved = pcall(dofile, path)
if not ok or type(saved) ~= "table" then saved = {} end

local fallback = type(saved.fallback) == "table" and saved.fallback or {}
local mode = fallback.mode or "2560x1440@240"
local scale = tostring(fallback.scale or 1.6)

if type(saved.outputs) == "table" then
    for output, entry in pairs(saved.outputs) do
        hl.monitor({
            output   = output,
            mode     = entry.mode or mode,
            position = "auto",
            scale    = tostring(entry.scale or scale),
        })
    end
end

hl.monitor({
    output   = "",
    mode     = mode,
    position = "auto",
    scale    = scale,
})

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})
