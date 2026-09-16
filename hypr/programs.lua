return {
    terminal       = "footclient",
    fileManager    = "dolphin",
    session        = "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'",
    menu           = "qs ipc call shell launcher",
    windowSwitcher = "qs ipc call shell windows",
    cpu            = "qs ipc call shell cpu",
    memory         = "qs ipc call shell memory",
    volume         = "qs ipc call shell volume",
    calendar       = "qs ipc call shell calendar",
    notifications  = "qs ipc call shell notifications",
    contributions  = "qs ipc call shell github",
    wallpaper      = "/home/gabriel/Documents/Wallpaper/12-Monterey-Dark.jpg",
}
