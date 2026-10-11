return {
    terminal       = "alacritty msg -s $XDG_RUNTIME_DIR/alacritty.sock create-window",
    -- terminal    = "footclient",
    fileManager    = "nautilus",
    browser        = "helium-browser",
    session        = "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'",
}
