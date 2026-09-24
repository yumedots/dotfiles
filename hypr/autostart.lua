local vars = require("programs")

hl.on("hyprland.start", function ()
  hl.exec_cmd("awww-daemon & foot --server & sh -c 'ulimit -Sn 65536; export __NV_DISABLE_EXPLICIT_SYNC=1; exec quickshell' &")
  hl.exec_cmd("pgrep -x wl-paste >/dev/null || wl-paste --watch cliphist store &")
end)

hl.exec_cmd("awww query 2>/dev/null | grep -qF 'image: " .. vars.wallpaper .. "' || for i in $(seq 1 10); do awww img '" .. vars.wallpaper .. "' && break; sleep 0.2; done")
