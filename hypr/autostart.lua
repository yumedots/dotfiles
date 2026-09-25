local vars = require("programs")

local path = (os.getenv("HOME") or "") .. "/.config/quickshell/cache/settings.lua"
local found = io.open(path, "r")
if found then found:close() end

local ok, prefs = pcall(dofile, path)
if not ok or type(prefs) ~= "table" then prefs = {} end

if not found then
  prefs = { wallpaper = vars.wallpaper }
  local handle = io.open(path, "w")
  if handle then
    handle:write("return {\n")
    for key, value in pairs(prefs) do
      handle:write("    " .. key .. " = " .. string.format("%q", value) .. ",\n")
    end
    handle:write("}\n")
    handle:close()
  end
end

local wallpaper = prefs.wallpaper or vars.wallpaper

hl.on("hyprland.start", function ()
  hl.exec_cmd("awww-daemon & foot --server & sh -c 'ulimit -Sn 65536; export __NV_DISABLE_EXPLICIT_SYNC=1; exec quickshell' &")
  hl.exec_cmd("pgrep -x wl-paste >/dev/null || wl-paste --watch cliphist store &")
end)

hl.exec_cmd("awww query 2>/dev/null | grep -qF '" .. wallpaper .. "' || { sleep 1; awww img '" .. wallpaper .. "'; }")
