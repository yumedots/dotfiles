local home = os.getenv("HOME") or ""

hl.env("PATH", table.concat({
  home .. "/.local/bin",
  home .. "/.opencode/bin",
  home .. "/.bun/bin",
  home .. "/go/bin",
  os.getenv("PATH") or "/usr/bin",
}, ":"))

hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("BROWSER", "helium-browser")