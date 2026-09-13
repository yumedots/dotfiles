# TODO

## Tooltips

- [x] Shared tooltip popup (Tooltip.qml: black, square edges, 1px gradient border taken from the Hyprland config through HyprBorder.qml), opens on demand, closes with a small delay so the pointer can travel into it (Config.tooltipCloseDelay)
- [ ] CPU tooltip
  - [ ] per core usage as a block grid, one block per core, github contribution graph style, color mixed red -> cpuBase by load
  - [ ] cpu model name, core/thread count and basic specs from /proc/cpuinfo
  - [ ] the process eating the most CPU (name + %)
- [ ] Memory tooltip
  - [ ] the process eating the most RAM (name + MB + %)
  - [ ] used / total / available / cached breakdown
- [x] Volume tooltip, a real mixer, laid out as a mixing console (VolumeMixer.qml, opened from VolumeStat)
  - [x] one column per stream, icon only: a vertical 4px pill fader, the percent, then the icon which is
        also the mute toggle (verified: app icons resolve, e.g. image://icon/chromium)
  - [x] the fader fills from the bottom, so half volume is a half pill, and a click anywhere on it jumps there
  - [x] only the apps with audio flowing: `pw-dump` polled while the popup is open, a node counts while its
        state is running. Config.mixerOnlyPlaying off keeps every app stream visible instead
  - [x] mute a single app without touching the sink (verified: the sink stays unmuted)
  - [x] outputs only: the apps that are recording are not channels, they only put a red dot on the mic line
        as a reminder (there is no input mixer, and no separator between the two)
  - [x] one stream, one channel, even for two windows of the same app: two Chromium streams sat side by side
        as two columns, and setting one to 35% left the other and the sink untouched (verified)
  - [x] the app faders on top, then the output and input devices below as DeviceLines that run the whole
        width of the widget: the device icon, a 4px horizontal pill and the percent flush at the right
        edge (verified: line 228 wide, the bar runs 34 -> 190.1 and the percent ends exactly at 228.0)
  - [x] how wide the widget is with nothing playing is Config.mixerIdleChannels columns (2), which is what
        the output / input bars stretch to: 78 long at rest, and they grow with the app columns past the
        cap. Config.mixerChannelWidth (72) sets the X size, Config.mixerFaderThickness (4) the fatness,
        Config.mixerDeviceIconSize (26) the icon on the output / input rows (verified: popup 174x82 idle
        with the bars 78.1 long, rows h26, 26px icons, app badges still 22). Raising mixerIdleChannels
        widens the resting widget and lengthens both bars by the same amount
  - [x] the percent is the mute toggle and the device icon opens the speaker / mic list, clicking a row
        makes it the default (verified: source muted and restored, picker opened listing both outputs).
        The active device is listed first and bright, the rest dim. The switch chevron and its reserved
        slot are gone, so the bar got its 22px back, and with a single device the icon is inert
        (verified: sink switchable -> icon clickable, source not -> disabled, percent still mutes)
  - [x] past Config.mixerVisibleChannels (5) an arrow pages the app row, one arrow each side, the left one
        only after you have paged, and the row slides with an eased 180ms. The cap really is 5 columns:
        with 7 apps playing the row is 400 wide but the window clips at 284 and exactly 5 columns are
        painted (counted from the pixels), the rest are behind the arrow
- [x] Date / clock tooltip = the calendar below

## Dev loop

- [x] gotcha: quickshell does not watch config.js. A config-only edit reloads nothing, so the change never
      reaches the running shell (`touch` is not enough either) — only a real .qml content change triggers
      the file watcher, and that reload does re-import config.js (verified with a marker logged from
      config.js: 0 reloads after editing it alone, 1 after a whitespace edit to shell.qml, marker printed).
      So after a config change, restart quickshell or make any .qml content change to trigger a reload

## Calendar

- [x] month grid, weekday column names, today inverted
- [x] two arrows each side: month (‹ ›) and year (« »), title click resets to today
- [x] rewritten from scratch, click the date component at the far right opens it, leaving it closes it (verified by screenshot: 220x174 logical, 1px gradient border)
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

## GitHub contributions widget

A quickshell bar widget showing the user's own GitHub contributions for the last 90 days as a
custom tile grid. Generic for any user, anonymous, no login, no token, nothing hardcoded: the
identity comes from the user's own git config at runtime.

- [ ] @username header, click opens https://github.com/<user> in the default browser
- [ ] 90-day tile grid, custom drawn (no GitHub assets), color ramp mixed from Config.contribBase
- [ ] tile click -> popup lists that day's contributions (repo, commit, type), each row
      clickable -> browser to github.com/<owner>/<repo>/commit/<sha>
- [ ] days with only private/unlisted contributions show the count + an "open profile" button
- [ ] works offline from cache after the first fetch

contrib.sh (one POSIX script, run via Process like MemoryStat.qml):

- [ ] resolve: `git config --get user.email`; if it matches `+<login>@users.noreply.github.com`
      the username is parsed from it offline, else fall back to the search API
      `api.github.com/search/users?q=<email> in:email` (only matches a public profile email),
      cache the login to ~/.config/quickshell/cache/gh-user
- [ ] calendar: GET `github.com/users/<user>/contributions?from=<90 days ago>&to=<today>`, parse
      the contribution-day tiles (data-date / data-level), cache to cache/calendar, output
      `date|level` lines

- [ ] events: GET `api.github.com/users/<user>/events`, cache to cache/events
- [ ] day <date>: filter the cached events for that date, output repo / commit sha / type
- [ ] open <url>: xdg-open
- [ ] cache dir ~/.config/quickshell/cache, recreated if missing; calendar refreshed every few
      hours, events hourly, day lists only filter the cache locally

ContribGrid.qml next to the other bar stats:

- [ ] Process runs contrib.sh, FileView reads the cache files, Timer sets the cadence
- [ ] header @username clickable, grid is ~13 weeks x 7 of our own Rectangles colored by level
      via helpers.mixColor, tile click -> Tooltip (Tooltip.qml pattern) with that day's events
- [ ] day with count > 0 but no events -> just the count + open profile button

Wiring:

- [ ] shell.qml: ContribGrid into the right Row, config.js: contribBase color + sizing,
      .gitignore: add /quickshell/cache

Contracts (know before building):

- the contributions endpoint is undocumented -> ponytail comment, upgrade path is GraphQL + PAT
- both the day detail and the window are 90 days and public-only because the events feed is the
  only anonymous source GitHub offers (same as the logged-out web); counts beyond that window are
  deliberately not fetched, history is out of scope
- private contributions (even publicized) never appear in the events feed, so those tiles show the
  count only
- anonymous API: 60 req/hr, hourly cache keeps it well under that

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
- check.js covers the desktop entry parsing, the app lookup, the calendar date helpers, the
  Hyprland border, gap and animation parsing and the pipewire stream parsing: node check.js
- PwNodePeakMonitor is unusable for the volume mixer on quickshell 0.3.1: it wants the capture stream's
  channels to match the node's, so a mono stream spams "is missing channels present in capture stream",
  and creating a monitor for every node of Pipewire.nodes segfaulted quickshell. The mixer instead polls
  `pw-dump` (Helpers.parseRunningStreams) and trusts `info.state == "running"`, which the daemon upgrades
  to running only while the stream actually drives the sink. Only polled while the tooltip is on screen
  (`Window.window.visible`), so a closed mixer costs nothing
- PwNode.properties comes back empty until a PwObjectTracker holds the node, so each stream row tracks its
  own node: the app name and the icon candidates all live in that map. isStream / isSink / type are
  constants (qmltypes marks them constant, they hold before the bind), media.class only arrives with the
  bind, so the tracker is gated on isStream and never on a value read out of properties: gating it on the
  properties-derived match both loops (tracker -> properties -> match -> tracker) and deadlocks input mode,
  where an empty media class classifies as output and the row would never get tracked at all
- PwNode.id is the node's global id, which is what pw-dump lists as the object id, so the running set from
  pw-dump matches the model directly (the pactl sink input index is object.serial instead)
- AppIcons.qml holds the .desktop grep and the icon resolution, shared by the dock and the volume mixer
  instead of each keeping its own copy. A stream only carries application.name / application.icon-name and
  those often miss (Helium is "helium" as an app but "helium-browser" as an icon), so the entry's Icon= is
  what actually resolves; Quickshell.hasThemeIcon(Config.dockFallbackIcon) is false on this box, which is why
  an app with no entry and no matching icon gets a glyph rather than a generic placeholder
- the border and the spacing are not configured in this repo: HyprBorder.qml (shared by the bar and
  every tooltip) asks Hyprland for `general:col.active_border`, `general:border_size` and
  `general:gaps_in` / `general:gaps_out` (hyprctl getoption -j) and asks again on the `configreloaded`
  event, so the hyprland config stays the single source of truth. `borderWidth` (-1) and
  `borderColors` (null) override it per tooltip, e.g. `borderWidth: 0` for no border
- the bar takes its whole spacing from those values: margins = gaps_out, the frame's padding =
  gaps_in, and exclusiveZone is just the bar's height, so hyprland's own gaps leave as much space
  below the bar as the bar has above it. The tooltip's padding is gaps_in as well, and it hangs
  gaps_out below the bar
- hyprctl prints colors as AARRGGBB, which is also what Qt parses an 8 digit hex string as, so
  "#" + the token is the color as is (ee33ccff -> opacity ee, rgb 33ccff). A value hyprland cannot
  express as plain hex is dropped and the border falls back to Config.borderFallbackColor
- the gradient border is a rotated rectangle the size of the diagonal clipped by the frame,
  with a hole cut by the background colored rectangle on top, because Qt's Gradient only offers
  Horizontal/Vertical orientation. Only the first and last color stop are used
- `anchorItem.Window.window` is a raw Qt window, not the Quickshell one, and setting it made the
  popup never show ("not a quickshell window"), so Tooltip takes the window explicitly
  (`anchorWindow: bar`) and takes its x from the anchor item with mapToItem
- mapToItem is not reactive, so a binding for the position was evaluated before layout and gave
  0,0 (popup off screen). Tooltip.refreshAnchor recomputes it every time the popup is shown
- anchor.rect.y is measured from the bottom edge of the anchor window, not its top, and quickshell
  adds the window's own margin on top of it, so `rect.y: 0` already lands the popup one bar margin
  (gaps_out) under the bar, which is the same spacing the bar gets from the screen edge. The x is
  clamped to the window width so a
  far right anchor (the date) still lands on screen. A bottom anchored tooltip (the dock) would
  need flipping up, which is not implemented yet


Make switching workspaces with the mouse wheel faster while holding the SUPER button
