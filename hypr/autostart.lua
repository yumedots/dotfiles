local path = (os.getenv("HOME") or "") .. "/.config/quickshell/cache/settings.lua"

local ok, prefs = pcall(dofile, path)
if not ok or type(prefs) ~= "table" then prefs = {} end

local function once(name, cmd)
  hl.exec_cmd("pgrep -x " .. name .. " >/dev/null || " .. cmd .. " &")
end

local cfg = (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config"))
local clipwatch = "sh -c 'wl-paste --watch cliphist store & exec wl-paste --watch \""
  .. cfg .. "/quickshell/scripts/qs-clipwatch\" text \""
  .. cfg .. "/quickshell/cache/launcher/clip-apps.txt\" \"$XDG_RUNTIME_DIR\"/qs-clipwatch.lock'"

local autostart = {
  { "awww-daemon", "awww-daemon" },
  -- { "foot", "foot --server" },
  { "alacritty", "alacritty --daemon --socket $XDG_RUNTIME_DIR/alacritty.sock" },
  { "quickshell", "sh -c 'ulimit -Sn 65536; export MALLOC_ARENA_MAX=2 MALLOC_TRIM_THRESHOLD_=65536 QSG_RENDER_LOOP=threaded; exec quickshell'" },
  { "wl-paste", clipwatch },
  { "polkit-gnome-au", "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1" },
}

hl.on("hyprland.start", function ()
  for _, app in ipairs(autostart) do once(app[1], app[2]) end

end)

if prefs.wallpaper then
  hl.exec_cmd("awww query 2>/dev/null | grep -qF '" .. prefs.wallpaper .. "' || { sleep 1; awww img '" .. prefs.wallpaper .. "'; }")
end
