local path = (os.getenv("HOME") or "") .. "/.config/quickshell/cache/settings.lua"

local ok, prefs = pcall(dofile, path)
if not ok or type(prefs) ~= "table" then prefs = {} end

local function once(name, cmd)
  hl.exec_cmd("pgrep -x " .. name .. " >/dev/null || " .. cmd .. " &")
end

local autostart = {
  { "awww-daemon", "awww-daemon" },
  -- { "foot", "foot --server" },
  { "alacritty", "alacritty --daemon --socket $XDG_RUNTIME_DIR/alacritty.sock" },
  { "quickshell", "sh -c 'ulimit -Sn 65536; export MALLOC_ARENA_MAX=2 MALLOC_TRIM_THRESHOLD_=65536 QSG_RENDER_LOOP=basic; exec quickshell'" },
  { "wl-paste", "wl-paste --watch cliphist store" },
  { "polkit-gnome-au", "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1" },
}

hl.on("hyprland.start", function ()
  for _, app in ipairs(autostart) do once(app[1], app[2]) end
end)

if prefs.wallpaper then
  hl.exec_cmd("awww query 2>/dev/null | grep -qF '" .. prefs.wallpaper .. "' || { sleep 1; awww img '" .. prefs.wallpaper .. "'; }")
end
