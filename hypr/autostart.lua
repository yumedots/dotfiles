local path = (os.getenv("HOME") or "") .. "/.config/quickshell/cache/settings.lua"

local ok, prefs = pcall(dofile, path)
if not ok or type(prefs) ~= "table" then prefs = {} end

hl.on("hyprland.start", function ()
  hl.exec_cmd("awww-daemon & foot --server & sh -c 'ulimit -Sn 65536; export __NV_DISABLE_EXPLICIT_SYNC=1; exec quickshell' &")
  hl.exec_cmd("pgrep -x wl-paste >/dev/null || wl-paste --watch cliphist store &")
end)

if prefs.wallpaper then
  hl.exec_cmd("awww query 2>/dev/null | grep -qF '" .. prefs.wallpaper .. "' || { sleep 1; awww img '" .. prefs.wallpaper .. "'; }")
end
