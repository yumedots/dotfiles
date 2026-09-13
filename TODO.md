# TODO

## Tooltips

- [ ] Shared tooltip popup (black, square edges, the same popup mechanism the calendar uses), opens on hover, closes with a small delay so the pointer can travel into it
- [ ] CPU tooltip
  - [ ] per core usage as a block grid, one block per core, github contribution graph style, color mixed red -> cpuBase by load
  - [ ] cpu model name, core/thread count and basic specs from /proc/cpuinfo
  - [ ] the process eating the most CPU (name + %)
- [ ] Memory tooltip
  - [ ] the process eating the most RAM (name + MB + %)
  - [ ] used / total / available / cached breakdown
- [ ] Volume tooltip, a real mixer
  - [ ] one row per app currently playing sound (icon, name, volume slider, mute toggle)
  - [ ] only the apps with audio flowing, via PwNodePeakMonitor on the Pipewire.nodes streams (PwNode.isStream)
  - [ ] default sink volume + mute at the top
  - [ ] mute a single app without touching the sink
- [ ] Date / clock tooltip = the calendar below

## Calendar

- [x] month grid, weekday column names, today inverted
- [x] footer with the day of the week, the date and how many days the month has
- [x] two arrows each side: month (‹ ›) and year (« »), title click resets to today
- [x] hovering a day moves the footer to that day, the day number is kept when changing month
- [x] hover the clock opens it, leaving closes it (verified with a real pointer)
- [ ] optional: week numbers, ISO week, holidays

## Dock

- [x] black, square edged dock centered at the bottom, floats over windows
- [x] every open window as an icon, grouped per app class, icons resolved from the .desktop files like fuzzel does
- [x] click focuses the closest window (this workspace first, then the most recent), clicking again cycles
- [x] round dot per running window in a stable per window order, the focused window's dot is bright,
  capped at Config.dockMaxDots (5) plus a + when the app has more windows than that
- [x] pinned shortcuts from Config.dockPinned, click launches when not running
- [x] fuzzel as the launchpad, rightmost item after a separator, click toggles it open and closed
- [ ] our own app launcher to replace fuzzel behind that button
- [x] fuzzel closes itself when focus leaves it (clicking an icon or a window dismisses it)
- [x] rounded corners (Config.dockRadius), extra space above the icons (Config.dockTopPadding)
- [x] no magnification
- [x] the reserved zone ends at the dock's top edge, so the only space left above it is the window gap from the Hyprland config (gaps_out), Config.dockGap adds more on request
- [x] new windows and new apps appear as soon as they open, and disappear when they close
- [x] a program running in a terminal window shows up as its own dock entry with its own .desktop
  icon (btop, yazi, nvim) and that window stops counting as one of the terminal's windows, click
  focuses it. Works through foot --server too, because the shell puts the command in the title
- [ ] right click to pin/unpin and to close a window from the dock
- [ ] app name label above the hovered icon, auto hide when idle
- [ ] indicator for apps with an urgent window

# Notes on this machine

- quickshell 0.3.1 (extra/quickshell) returns 0 entries from DesktopEntries.applications, byId and
  heuristicLookup, so app icons come from helpers.parseDesktopEntries over `grep -H` of the .desktop
  files: id, then StartupWMClass, then Exec basename, then the lowercased Name
- a second PanelWindow inside Variants kills the first one, the bar and the dock have to be siblings
  inside a ShellRoot
- HyprlandToplevel.address has no 0x prefix, dispatching needs it added back:
  hl.dsp.focus({ window = "address:0x..." }) (or focuswindow address:0x... on a classic config)
- a freshly opened window arrives in Hyprland.toplevels with an empty lastIpcObject (no class, no pid),
  so classOf() returned "" and the window was skipped. Hyprland.refreshToplevels() fills it in, which
  is why the dock only refreshed on movewindow/changefloatingmode before
- a block bodied `property var` binding that reads Hyprland.toplevels.values does not re-evaluate when
  the model changes (a plain `toplevels.length` binding does), so the dock recomputes its app list
  imperatively on Hyprland window events instead of binding it
- with foot --server every window reports the server's pid (all footclient windows share pid 1287),
  so the program running inside a window cannot be identified from the window. A terminal that owns
  its window does report its own pid (plain `foot -e btop` -> foot pid, btop as its child), which is
  what an in terminal app detection needs
- a terminal window's dock identity comes from its title: helpers.commandWord takes the first word
  of the title and only accepts a bare name (no / and no ~), so a shell prompt title never matches.
  oh-my-zsh's termsupport already puts the running command in the title (omz_termsupport_preexec),
  no plugin needed, and it works through foot --server because the title is per window
- zsh is the shell for new terminals: oh-my-zsh in ~/.oh-my-zsh, config in ~/.config/zsh/.zshrc,
  ~/.zshenv only sets ZDOTDIR, foot.ini has shell=/usr/sbin/zsh, and ~/.zshrc was removed. The login
  shell itself still needs `chsh -s /usr/sbin/zsh` (it wants a password), and until either that or a
  foot --server restart happens, windows spawned by the old server still run bash
- Hyprland.activeToplevel is the reliable "which window is focused", toplevel.activated lags
- while a layer surface holds exclusive keyboard focus (fuzzel's default), Hyprland drops pointer
  clicks on our other layer surfaces, so the bar and dock look dead under it (clicks on normal
  windows still work). fuzzel is launched with --keyboard-focus=on-demand from the dock, typing still
  reaches it, and then the launcher button can toggle it
- the launcher keeps its own open/closed state (a 400ms pgrep poll syncs it) instead of checking
  pgrep on click, because fuzzel exits on keyboard focus loss and would otherwise be relaunched
- tmp test tools (not part of the config, they live in /tmp and vanish on reboot): /tmp/vp/vpclick is
  a small zwlr_virtual_pointer_manager_v1 client that injects move/click/scroll, /tmp/bin has wtype
  so keys can be typed into a focused surface
- check.js covers the desktop entry parsing, the app lookup and the calendar date helpers: node check.js


Make switching workspaces with the mouse wheel faster while holding the SUPER button
