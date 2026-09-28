return {
    terminal       = "footclient",
    fileManager    = "nautilus",
    session        = "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'",
}
