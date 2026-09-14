# TODO

## Layout

- hypr/: hyprland.lua is the entry point and only `require`s the rest - monitors.lua, programs.lua
  (terminal, fileManager, menu, windowSwitcher, wallpaper), envs.lua, looknfeel.lua, layouts.lua,
  input.lua, binds.lua, rules.lua, autostart.lua. Editing a topic means editing its own file, and the
  terminal the launcher reads lives in programs.lua
- quickshell/ is laid out one folder per thing, the entry file doing nothing but hosting them:
      shell.qml          the composition root: the IpcHandler, a bar per screen, the dock, the launcher
      config.js          every knob, at the root so it is the first file you see
      lib/               helpers.js (the parsing and the formatting) and check.js (the self-check)
      ui/                the shared primitives every surface draws with: HyprBorder, Tooltip, BarStat,
                         BarText, Selector (the one keyboard list the launcher, the process lists and the
                         window switcher scroll with), ProcessList, SearchField (the one search box the
                         launcher and both monitor cards draw), and a qmldir that names them
      services/          AppIcons, the shared .desktop entry and icon lookup, no surface of its own
      topbarlayout.json  what the bar holds and where: left / center / right slots, position,
                         transparent, centerAnchor, and a settings blob per entry
      bar/               Bar.qml, the bar surface, and bar/widgets/ (Workspaces, Clock, Date, Tray,
                         CpuStat, MemoryStat, VolumeStat, Spacer), each stat owning its tooltip's wiring
      tooltips/          Calendar, CpuMonitor, MemoryMonitor, VolumeMixer, one file each
      dock/, launcher/   the other two surfaces
      cache/             the gitignored state: pins, usage
- the shared folders are real QML modules and the `qmldir` is what names what each one exposes, so
  nothing spells a `../..` path any more: `import qs` for the root module (Config and Helpers),
  `import qs.ui` for the primitives and `import qs.services` for AppIcons. Verified: a qmldir can
  expose a .js file directly, the `as Config` alias is then not needed, a `.pragma library` file works
  and a module folder can be lowercase (checked on a scratch shell, then on the live one)
- gotcha: the module at the shell root is what declares config.js, because config.js sits at the root
  and a qmldir can only name files inside its own folder. A qmldir entry pointing at a missing file
  fails the whole module and the whole config with it ("File not found"), silently at first: that is
  how lib/qmldir kept the shell from loading for a few minutes, and why lib/ no longer has one
- no comments in the config files (the hyprland example comments were stripped): the why, the
  measurements and the gotchas live here and in LAUNCHER.md
- the shell's own launcher shortcuts point at the real paths, e.g. "Edit shell config" opens
  quickshell/config.js and "Edit hyprland config" opens ~/.config/hypr (the folder, not one file)
- sway/ and waybar/ are gone: nothing here uses them any more
- topbarlayout.json is what the bar is built from, not the QML: bar.position (top/bottom),
  bar.transparent, bar.centerAnchor (the entry the center row is pinned around, so the clock stays
  centered while the rows beside it change width) and bar.layout.left/center/right as lists of
  { "id": ... } entries that each carry their own settings (a spacer takes `size`, the clock a
  `format`). Bar.qml maps an id to a component (componentFor) and hands the entry to the widget as
  `settings`, so adding a widget is a file edit plus one case; the default layout is the right slot
  the bar has always had (workspaces | clock | tray, cpu, memory, volume, date). Helpers.parseBarLayout
  is pure and check.js covers it (missing file, broken JSON, a slot that is not a list, a position
  that is neither top nor bottom, entries with no id all fall back; an explicitly empty slot stays
  empty). It hot reloads without a restart: the FileView sets watchChanges and calls reload() on
  fileChanged, and bar.layout is a binding over its text() - verified by flipping `transparent` and
  watching the bar band go from #101010 to the wallpaper and back, twice
- the widget keys are the other half of the launcher's IpcHandler: MOD+Z cpu, MOD+X memory, MOD+C
  volume, MOD+S calendar (hypr/binds.lua -> hypr/programs.lua -> `qs ipc call shell <name>`), and
  shell.qml calls bars.instances[0].toggleWidget(id). That indirection is the fix, not decoration:
  Bar.toggleWidget -> openExclusive closes whichever card is open before opening the next (only one
  widget on screen, kept from the earlier pass), and going through the bar's own registry of live
  widgets is what never worked before - the click path called root.toggle() inside Bar, where the root
  id is `bar`, so every click from the bar threw a ReferenceError and only the widgets whose handles
  were reachable elsewhere still opened. The keys use named keys, so a bound key cannot be a stale
  object reference

## Tooltips

- [x] BUG, the first open after a cold start showed the card's bottom stretched with the row colours
      smeared down it, and only on the cpu and memory cards. Cause: a layer surface is mapped before its
      content has been laid out, so the surface is born at the pre-layout height and then resized a few
      frames later; the compositor presents the old, small buffer stretched into the new size. Not a
      Quickshell-side number (`root.height` was already the final 272 from the first 16ms tick) - polling
      `hyprctl -j layers` after the open showed the surface at h=73 for 40-78ms and 272 from 78ms on,
      which is also why the second open was always fine (the content is laid out by then). The card is
      mapped straight away now but its border is hidden (`visible: root.revealed`) until a 140ms warmup
      timer has passed, so the resize happens while the surface draws nothing. Verified: four frames
      grabbed in a row after a cold first open are empty, empty, empty, then the full 87..517 card - no
      small or stretched frame in between, and the second open is unchanged
- [x] Shared tooltip popup (Tooltip.qml: black, square edges, 1px gradient border taken from the Hyprland config through HyprBorder.qml), opens on demand, closes with a small delay so the pointer can travel into it (Config.tooltipCloseDelay)
- [x] CPU tooltip (CpuMonitor.qml, opened by clicking CpuStat like the calendar / mixer)
  - [x] per core usage as a block grid, one block per core, github contribution graph style, the color mixed
        Config.cpuIdle -> Config.cpuBase by load: no usage is a dark grey, and load is what paints the
        purple, so a busy core stands out against the quiet ones instead of the whole grid being one
        bright purple (the bar's own stat and the % texts in the card keep cpuBase -> red, the ramp the
        bar has always used, and they are text on black so they stay legible). Config.cpuBlockColumns (16)
        columns, the block size is derived from Config.cpuTooltipWidth so a full row always spans the
        card, the gap is Config.cpuBlockGap (4). Verified from the pixels: blocks 11.25 logical square on
        a 15.25 pitch, 16 per row, 56 threads as 4 rows, an idle core painted #2f2f2f (= cpuIdle) and a
        loaded one landing between that and #a78bfa (= cpuBase), on a #000000 card
  - [x] the model name (title, elided) with the overall load next to it, then the specs from
        /proc/cpuinfo, e.g. `56 threads · 14 cores · 3.3 GHz · 35 MB` (cache is KB -> MB, the clock is the
        fastest one in the file, missing keys are dropped from the line). The title and the specs line
        are on the card's own ladder: the title is Config.foreground, the specs and the "Top processes"
        heading are Config.cpuBase (the card's purple), so the card reads as one thing with the grid
  - [x] the top CPU processes: name left (elided) in Config.foreground and the percentage right in
        cpuBase -> red, the same load ramp as the overall % in the title (the names went purple for a
        pass and were asked back to white: the purple is the card's, the rows stay readable).
        `ps -eo pcpu=,comm= --sort=-pcpu` re-run every 2s, the sampler's own `ps` (and its zombie)
        filtered out with Config.psIgnore: pcpu is an average over the process life, so the fresh
        `ps` was showing up at 100-200% and topping the list (seen in the probe). The list is not capped:
        every process `ps` reports is in it (647 here) and Config.cpuTopCount (5) is how many rows fit
        before it scrolls: the rows live
        in ProcessList.qml (a shared viewport: spacing Config.procsGap 6, row height from a hidden
        prototype Text, delegate width/height read off ListView.view.rowWidth/rowHeight, and a 3px
        Config.muted rounded scrollbar pinned to the card's right edge, taller than the track only when
        there is more to see). Verified on a scratch instance: procs 30, listH 94 = 5*14 + 4*6, contentH
        594 = 30*14 + 29*6, thumb 15 tall at y 0 and y 79 (= the full 94-15 track) at the two ends, row
        width 231 = the 240 list minus the thumb and the gap, and 21 thumb pixels in a screenshot of the
        real card
  - [x] BUG, the rows were invisible for a while and this is why: rowHeight/rowWidth were declared on
        the ProcessList *root Item* and read in the delegate as ListView.view.rowWidth, but
        ListView.view is the ListView, not the Item holding it, so both resolved to undefined and every
        delegate was created 0x0. contentHeight still came out right (30 delegates of 0 + 29 gaps of 6 =
        174) and the scrollbar still drew, which is why it looked like a styling problem instead of a
        sizing one. The two properties now live on the ListView itself (rowWidth takes the width, the
        scrollbar and the spacing off its own geometry). Verified: delegate 14x231, and the pixel runs
        that used to read 0 white pixels in the list band now read 339 (cpu card) and 585 (memory card)
  - [x] /proc/stat has exactly one reader: the bar's CpuStat (Helpers.parseCpuStat + cpuPercents, every
        2s, a 150ms second sample on the first read so the bar does not sit at 0% for two seconds). It
        exposes `pct` and `cores`, and the tooltip's CpuMonitor takes them through `source` (shell.qml:
        `CpuMonitor { source: cpuStat }`), so the bar and its widget can no longer disagree (before this
        each had its own FileView and cadence, and 1% next to 2% was normal) and the per core grid comes
        from the same delta as the number above it. Opening the popup calls source.refresh() to take a
        fresh sample. Verified: bar=1.8649 tooltip=1.8649 equal=true, barCores=56 tooltipCores=56
        sameArray=true, bar text "2%" against the monitor's Math.round 2%
  - [x] verified content box 264x241 logical (it was 264x201 with three process rows, so the taller
        viewport is exactly the 2 extra rows of 20), fade and border from the shared Tooltip /
        HyprBorder, no warnings on load, node lib/check.js covers the parsing and the clamping
- [x] Memory tooltip (MemoryMonitor.qml, opened by clicking MemoryStat like the cpu one)
  - [x] /proc/meminfo is parsed once, in the bar's MemoryStat (Helpers.parseMeminfo), and the card takes
        it through `source` (shell.qml: `MemoryMonitor { source: memoryStat }`), so the bar's number and
        the widget's cannot drift - the same fix the cpu tooltip needed. MemoryStat keeps the bar label
        it had (used GB, e.g. "4.0G") and now also exposes the whole parsed record. Verified:
        bar=12.703 tooltip=12.703 equal=true, total 32763188 kB, used total-available, available/cached/
        buffers read back against /proc/meminfo
  - [x] used of total, then available and cached on their own line (Helpers.gbText, kB -> GB with one
        decimal), then a 4px usage bar in Config.dim with the load colour filling it, then the top
        processes by RSS
  - [x] the process eating the most RAM: `ps -eo rss=,comm= --sort=-rss` re-run every 2s while the card
        is on screen, uncapped like the cpu card and shown Config.memoryTopCount (5) rows at a
        time with the same ProcessList viewport as the cpu card (Config.psIgnore drops the sampler's own
        `ps`). Each row is just `name` in Config.foreground and the amount right aligned in
        Config.memoryBase: Helpers.sizeText picks the unit from the size, GB at a gigabyte or more, then
        MB, then KB, so `800.7 MB`, `4.2 GB` and `0 KB` all read right. The gauge bar behind the row and
        the percentage were both dropped on request - the list is there to say how much RAM a process
        holds, not how big a slice of the card it deserves
  - [x] swap is counted in everything, not drawn beside it: Helpers.parseMeminfo now returns `pool`
        (total + swapTotal), `committed`        (used + swapUsed), `free` (pool - committed - cached - buffers, so reclaimable memory counts as
        free and so does free swap, with `ramFree` and `swapFree` kept apart for the two sides of the
        bar) and `pct` (committed over the pool, not just ram). One parser means the bar widget's percentage, its colour and the card's whole header are
        the same numbers. Verified: pool 36957488, committed 4368640 = used + swapUsed, free 29999256,
        and used + cached + buffers + swapUsed + free = the pool exactly, so the bar always fills 100%
  - [x] one stacked bar holds the picture, flat, ram cut off from swap, and each pool gets the room it
        is worth: the bar is scaled by the pool (total + swapTotal), so the ram side takes
        total/pool and the swap side swapTotal/pool of the width, then each side is filled with its own
        used / free split - a bigger swap really does get a wider slot (88.7% ram against 11.3% swap on
        this box, 213px against 27px). Slices: used (danger scale) / cached / buffers / ram free, then
        Config.memorySeparator (2) in Config.background, then swap used / swap free. The divider is a
        slice of its own so it reads as a cut between the two pools rather than another colour, and the
        free slices are Config.memoryFree (#ffffff) on both sides, one rule: free memory is white. A
        vertical gradient was tried here and taken back out. The legend repeats the same colours in the
        same order (used / cached / buffers / swap / free, free last). Verified from the pixels along the
        bar: used #8ed081 to x70.6, cached #44774f to x86.9, buffers #25412b for 0.7, white free to
        x253.1, the 2px black divider, white free swap to the end; segments 28.8 + 16.2 + 0.7 + 165.3 +
        2 + 0 + 27 = 240.00 = the card's inner width
  - [x] a danger meter instead of a straight ramp, so red only shows up when it means something:
        Helpers.dangerColor(base, warn, danger, warnAt, dangerAt, pct) stays on memoryBase and walks to
        memoryWarn by Config.memoryWarnAt (60), then to memoryDanger by Config.memoryDangerAt (85), then
        holds. Used by the bar slice, the header percentage and the bar widget's own colour
        (MemoryStat), and by every row of the process list, where the colour is the share of the pool
        that process holds (a 300 MB process sits on memoryBase, a 40% hog lands in the red). The old
        straight mixColors(memoryBase, red, pct/100) is what made everything look half alarming.
        Verified: 10% #8bd184, 60% #d8b04a, 75% #dd784f, 90% #e05252, and the live rows came out
        #7ed78c for the 2% top process. memorySwap also moved off the warm tones to a cool #7f8fd8,
        since the amber now belongs to the warning scale
  - [x] rows on this box: `used 4.2 GB`, `cached 2.4 GB`, `buffers 105.4 MB`, `free 28.6 GB`,
        `swap 0 KB of 4.0 GB` (0 KB rather than 0 B, which is the unit rule the sizes follow)
  - [x] the card is the memory equivalent of the cpu one: the title is Config.foreground, the committed
        of pool line, the "Top memory" heading and the row amounts are Config.memoryBase (green), the
        row names white. Content box 264x292 logical, everything inside the card's width (the figures are
        right aligned and the names elide), no warnings on load
  - [x] the cpu card is back to 264x241: a load average line was added under its specs and then asked
        out again, so Helpers.parseLoadavg and its asserts went with it (no dead code left behind)
  - [x] the shared plumbing this needed: the stat's clicked/exited/hover moved into BarStat.qml (it was
        copied into CpuStat and VolumeStat, and MemoryStat would have been a third copy), and the process
        viewport became ProcessList.qml, so both cards scroll the same way (the cpu content box measured
        the same 264x241 before and after the refactor)
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
- [x] the search box is one primitive, shared, not a copy per card: ui/SearchField.qml (also what the
      launcher types into) is the box, the prompt glyph, the placeholder, the `f` hint and the key
      handling; the monitor cards only pass a size and a few knobs. In a card the heading and the field
      share one full-width band in Config.launcherSearchBox, which doubles as the separator between the
      meters above and the list below - measured on the cpu card: the band runs its whole 282 width, 27
      tall, the white glyph at x230-242 with the muted `f` keycap beside it, the heading at the left
      (verified from a screenshot). `f` opens the field and pins the card (Tooltip.pinned =
      monitor.searching, so the close timer cannot fire while you type), Escape clears it, `q` force
      quits the highlighted process (Helpers.killCommand + Config.procKillSignal) and arrows / hjkl move
      the selection in the shared ProcessList. Typing filters every process, not just the top N:
      Helpers.filterProcesses over the same parsed `ps` output, uncapped like the list itself
- [x] Date / clock tooltip = the calendar below

## Input

- [x] one selector primitive, ui/Selector.qml, is what every list scrolls with: the launcher, both
      monitor process lists and the window switcher get the highlight, the immediate scroll (contentY is
      set, nothing animates, so the highlighted row is the row that moves) and the same 3px scrollbar
      from one place. The process lists had grown their own ListView + highlight + wheel handler, which
      is why the selection lagged the pointer, jumped rows and slid instead of moving
- [x] quickshell is keyboard only: no MouseArea, TapHandler or WheelHandler left outside the dock, and
      every TextInput has selectByMouse: false. Widgets open and close with their MOD bind (z / x / c /
      s through `qs ipc call shell <name>`) and close with Escape; the launcher and its window switcher
      close with Escape; the calendar moves with hjkl / arrows and the mixer with h l and j k + Enter
- [x] the search field shows one hint, `f to type` (Config.procSearchHint), in the glyph's fixed slot,
      instead of a `f` keycap followed by a separate "Type to search" line. The box hugs its own content
      (the hint text, not a fixed width: a fixed 120 made the field 149 wide, and since it is anchored
      right that put its glyph at x95 on top of the end of the "Top processes" heading at x106). It is
      measured now: field x146 w94, icon at 150..163, hint at 171..236, heading ends at 106. While a
      filter is open the field takes exactly the room left of the heading (band - heading - 3*spacing)
      instead of Math.max(implicitWidth, ...), so widening it can never reach back over the heading
- [x] hjkl reaches the lists through one focus owner. The card root has `focus: true` and forwards
      keys: f opens the filter, Escape closes, anything else goes to the shared ProcessList (so hjkl and
      q work with no filter open). While the filter is open the input owns the letters, arrows move the
      selection (onNavigate) and only q is taken back for the kill - typing "hypr" would otherwise move
      the highlight four times. `f`/Escape while the filter is open are the input's, and the card root
      returns `true` from onPressed only through the selector, so a key is never both a movement and a
      character. Verified against the live shell by injecting keys (hyprctl dispatch
      'hl.dsp.send_key_state({ mods = 0, key = "j", state = "down" })'): the highlight walked with
      j j j, h walked it back up a page, f opened the filter, h y p filtered 200 -> 200 -> 2 without
      moving the selection, Down moved it, Escape cleared and a second Escape closed the card, and q on
      a searched process killed the `sleep 300` started for the test
- [x] the highlight survives the list repainting. `procs` is a new array every 2s poll, and a fresh
      model resets the ListView's currentIndex to 0, so the selection snapped back to the top mid-navi-
      gation. Selector now keeps its own currentIndex as the source of truth, re-applies it on
      onModelChanged (immediately and once more via Qt.callLater, in case the refill lands after the
      handler) and the model is only ever written back through the selector. Verified: highlight at row
      3 stayed at row 3 across two polls that before moved it back to row 0
- [x] the highlight is a plain rectangle (radius 0). It was radius 2, and because the ListView clips
      the highlight at scrollWidth + rowSpacing the right corners were cut mid-radius, which is why the
      launcher looked rounded and the cards looked rounded on one side only. Verified from the pixels:
      all four corners of the 231x14 highlight are solid #2f2f2f
- [x] "Nothing matches" (Config.procNoMatch) is centred in the box the rows would have used: the
      message takes `height: procList.implicitHeight` with AlignVCenter and the empty list is hidden,
      where before the list kept its height and the message added a line under it, stretching the card
      517 -> 549 physical and pinning the text to the bottom. Verified: the card is back to 87..517 and
      the message sits at y403..417 inside the 336..486 list band, the same pattern the launcher already
      uses for its empty state (an Item the height of the list with the Text centred in it)
- [x] the selection is anchored to the process, not the row number. Keeping the row still is not
      enough on its own: both lists are re-sorted every poll, so the row under the highlight became a
      different process every 2s (much more visible on the RAM card, where RSS reorders far more than
      pcpu does - that is the "highlighter jumps" that was left). Selector now takes a `keyField`
      (ProcessList passes "pid"), remembers the selected key on every move and, on each model change,
      reselects the row that key is now on; if the process is gone it keeps the row. Verified from the
      pixels: the name inside the highlight rendered byte-identical ("Helium") before and after a poll
      that moved the highlight from y368 to y400. Set `keyField: ""` in ProcessList.qml to go back to
      row-stable instead (one line, no other change)
- [x] every process is listed, not the top 30. Config.cpuTopMax / memoryTopMax (30) and procSearchMax
      (200) are gone and the helpers are called without a max (`max > 0` was the only thing that sliced).
      This machine has 648 `ps` rows, so the cards were showing 5% of them and a search for "h" stopped
      at 200 (it is 217 now). Verified through the same helpers in node against the real `ps` output:
      648 parsed, 647 after Config.psIgnore, and the card's scrollbar thumb is now at its 12px floor
      (it was 14.9 logical with 30 rows), which is what a 12000px content height looks like
- [x] the "Top processes" heading has the same inset as the search bar: `anchors.leftMargin:
      Config.procSearchPadding` instead of Config.spacing. Measured off the band: the heading ink used
      to start 11.9 logical from the left edge while the `f to type` hint ended 4.4 from the right,
      now both are 4
- [ ] the tray lost its click handler with the rest of the mouse code and has no keyboard path yet:
      it needs a selection over the icons (h l) and Enter / Shift+Enter to activate

## Dev loop

- [x] gotcha: quickshell does not watch config.js. A config-only edit reloads nothing, so the change never
      reaches the running shell (`touch` is not enough either) — only a real .qml content change triggers
      the file watcher, and that reload does re-import config.js (verified with a marker logged from
      config.js: 0 reloads after editing it alone, 1 after a whitespace edit to shell.qml, marker printed).
      So after a config change, restart quickshell or make any .qml content change to trigger a reload
- [x] hyprland config is Lua here (0.56), so `hyprctl keyword <opt> <value>` fails with "keyword can't
      work with non-legacy parsers. Use eval". Use `hyprctl eval 'hl.config({ general = { gaps_out = 8 } })'`
      for a temporary change and `hyprctl reload` to re-read the file. Dispatch
      needs the same form: `hyprctl dispatch 'hl.dsp.focus({ workspace = 1 })'` (`hl.dsp.workspace` is
      not callable). Opening/closing the launcher moves focus, which can make Hyprland switch to the
      window it restores, so pin the workspace again before comparing two screenshots

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
- [x] the launchpad button toggles the shell's own launcher (see below), no fuzzel process behind it
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

## App launcher

Replaces fuzzel: a layer surface inside the shell with exclusive keyboard focus, toggled through an
IpcHandler so the Hyprland bind and the dock's launchpad button both just toggle it. The card is
HyprBorder, the same primitive behind the bar and every tooltip, so the border, the background and
the fade duration come from the Hyprland config and match the rest of the shell.

- [x] ALT + SPACE (`qs ipc call shell launcher`) and the dock's launchpad button open it (Dock emits
      launcherRequested, no fuzzel process anywhere). Escape, Enter after running something or a click
      outside the card closes it. Verified through the live shell: the ipc call exits 0 and the surface
      maps as namespace launcher on the overlay layer with exclusive keyboard focus
- [x] shaped like the old fuzzel: a narrow vertical card centred on the screen, 270x400 with twelve 28px
      rows, 20px row icons, a 24px icon column and 16px text (measured on a scratch instance: cardW=270,
      cardH=400 = 12*28 + the 30px input, the 8px column gap, 2*12px padding and 2*1px border, inset 13;
      cardW/cardH/listHeight all come from Config). The width trades against height, so the card grows in Y (launcherMaxRows), not in X
      (launcherWidth); the row is 28 so the highlight band is 28 tall and its content (icon and name,
      both centred) sits in the middle of it (probe: row h=28 highlight=28 iconSize=20 for every row).
      The size is constant whatever the list holds: listHeight is always launcherMaxRows * rowHeight, so
      22 results, 1 result, 0 results, every prefix mode and the window switcher all measure 270x400 on
      a scratch instance (listHeight 336 = 12*28) and the card 434x237.5 logical through the live
      shell's compositor (the couple of pixels are the border, which the pixel run does not count)
- [x] one text size and one icon size everywhere in the card, taken from the search bar: the prompt glyph
      and every row icon / row pin glyph are Config.launcherIconSize (20), the typed text, the placeholder
      and the row names are Config.launcherFontSize (16). Before this the prompt was fontSize+2, the input
      fontSize+1, the pin iconSize-4 and the rows 15px, so the card mixed four glyph sizes. The highlight
      band was briefly raised to the field's height (30) and is back to Config.launcherRowHeight (28) on
      request. Verified: scratch probe field 244x30 with glyphPS=20 inputPS=16 and row h=28 hl=244x28
      (field band 48 device px, highlight band 44.8 at a 1.6 scale)
      (the empty-state row reserves the same list height, otherwise Column.implicitHeight drops the
      hidden ListView and the card collapsed to 270x84 with no matches). The empty-state message ("nothing
      matches", "no windows open") is centred in that empty area, horizontally in the card and
      vertically in the list: measured from a screenshot, x-centroid 134.3 against the card
      centre 135.0, band y 186-200 against the list centre 193
- [x] the search icon owns a fixed slot and the row icons sit directly below it: Config.launcherIconSlot
      (24) is the glyph's width (centred in it, prompt is U+EA6D), each row icon is centred in that same
      0..24 column (a 20px icon lands at x=2) and the input and the names both start at the slot's right
      edge plus Config.launcherTextGap (10), i.e. 34, so nothing shifts as you type and the text lines up
      with the search field (probe: glyph x=0 w=24, rows iconX=2 iconW=20 nameX=34, input x=34 inputRight=234).
      The field's placeholder reads "Type to search..." in both lists and the empty-state messages are
      capitalised: "Nothing matches", "No windows open", "Nothing copied yet", "Type two letters or more
      to search $HOME"
- [x] the search field sits in its own box and the card is the shared surface colour: the field row is a Rectangle in
      Config.launcherSearchBox (#1f1f1f, a dark grey that does not burn at night, measured 244x30 = the
      card's inner width) and HyprBorder gained an overridable `backgroundColor` (default Config.surfaceTranslucent)
      that the launcher sets to the same shared value. The
      selected row is Config.launcherHighlight (#2f2f2f) instead of a full white flash and the text and
      icon on it are Config.launcherHighlightText (probe: row0 highlight=#2f2f2f nameColor=#ffffff,
      row1 highlight=#00000000)
- [x] the appear fade is the widget one (borderOpacity: Math.pow(opacity, 8) plus the opacity Behavior at
      card.appearDuration), verified through the fade: opacity 1.000 -> 0.209 -> 0.000 with the border at
      0.000 while it is still descending, so no gradient flash. What is gone is the *scroll* animation:
      the list is interactive: false with a WheelHandler that sets contentY directly, so the wheel jumps
      one notch (60px) with no glide and a drag-release cannot coast. (The earlier "delete the animation"
      pass removed the appear fade by mistake; restored)
- [x] the card is centred in the strip *below* the bar, not on the whole screen: the launcher's surface
      respects the bar's exclusive zone, so its window is 854 tall on this 900-tall screen (card at
      window y 253, screen y 299). Clicking above the card but over the bar does not close it
- [x] prompt is the search glyph (U+EA6D) while the query is plain or in the window switcher, and
      switches to the mode glyph (`.`, `$`) once a prefix is typed
- [x] search field with fuzzy matching, arrows move the highlight exactly one row, Enter runs the
      highlighted entry. Arrows clamp at both ends like fuzzel's `next`/`prev` ("does not wrap around
      when the last entry has been reached"): move(step) is a Math.min/max clamp, not a modulo, so the
      last item stays the last item instead of jumping back to the top (verified on a scratch instance:
      index 0 -> down x12 -> 12, down x40 -> 25 = count-1, up x60 -> 0)
- [x] the row under the cursor must not grab the highlight while the list slides underneath a stationary
      pointer, which is what made one arrow key skip rows: the delegate compares the pointer's *scene*
      position (row.mapToItem(null, mouse.x, mouse.y), which is invariant under a scroll - verified
      list.mapToItem(null,0,0) = the card's inner origin 836,-25) against root.hoverScene and only takes
      the index when it moved. A synthetic pointer is impossible on this box (no xdotool/ydotool/wtype,
      /dev/uinput is root-only, Hyprland's lua API has no cursor dispatcher), so the event half of it is
      unverified here: the probe's stationary pointer never enters the surface at all (hoverScene stays
      -1,-1 even with a row under it), so fixed and pre-fix builds behave identically in the probe
- [x] sources: desktop apps (AppIcons/.desktop entries, NoDisplay, Hidden, entries with no Exec and
      Config.launcherIgnoreApps skipped: 29 entries before the ignore list, 26 after), commands from
      Config.launcherCommands, session actions from Config.launcherActions. Open windows are *not* here
      any more: they live in the window switcher below (allEntries has 22 entries, 0 of them windows)
- [x] window switcher: MOD + TAB (`qs ipc call shell windows`,      IpcHandler function windows() ->
      launcherWindow.toggleWindows()) reuses the same card, only the list differs (still 270x400, same
      search glyph prompt and the same "Type to search" placeholder; each row keeps the window glyph
      U+F05B1). It lists
      every open window, most recently
      used first, straight from Hyprland's focusHistoryID - verified against `hyprctl clients`: the
      switcher shows code-insiders(0), helium(1), footclient(2), footclient(3) in exactly that order.
      Typing filters on title and class ("term" leaves the Nerd Fonts helium window), arrows/Enter work
      like the launcher, app icons come from the same AppIcons lookup. MOD+TAB again closes, and the
      apps launcher (ALT+SPACE, dock) always reopens in apps mode. The bind is live: hyprctl binds shows
      modmask 64 key TAB
- [x] session actions run as the user, no sudo, cleared with login1 first: suspend, logout, reboot,
      shutdown (CanSuspend/CanReboot/CanPowerOff all answer yes, CanHibernate is na on this box). Lock
      is deliberately absent: no locker is installed (no hyprlock/swaylock), so `loginctl lock-session`
      would do nothing. Glyphs (all present in Hack Nerd Font, all confirmed to paint ink when rendered):
      suspend U+F04B2, reboot U+EAD2, shutdown U+F011, logout U+F0342
- [x] apps launch through `sh -c` with the full Exec line and the field codes stripped, so arguments
      and `env VAR=…` wrappers survive (previously only the first token ran, so `--new-window` and
      friends were dropped and an env wrapper would have run `env` itself)
- [x] the calculator needs no prefix, Spotlight style: Helpers.calcEntry(query) returns a row when the
      query has a digit and the whole thing parses, and buildResults puts it above the matching items, so
      the result and the entries that match the number are in the same list (probe: "2*(3+4)" ->
      ["calc|2*(3+4) = 14"], "7" -> no calculator row and no matches, "e" and "firefox" stay a search).
      Enter copies the result with wl-copy, which cliphist then stores
- [x] prefixes: `.` file search under $HOME, `$` clipboard history. The clipboard is the system's own
      (cliphist): `cliphist list` is read (Helpers.parseClipboardList splits `id\tpreview`) and Enter runs
      `cliphist decode <id> | wl-copy` (probe: `$` listed 3 real clips with their ids 5/2/1), so anything
      else that stores to cliphist shows up here too. The shell's own file-per-clip watcher
      (clipboard.sh, CLIPBOARD_KEEP, the clipWatch process) is gone, and the store side now runs from
      hypr/autostart.lua: `pgrep -x wl-paste >/dev/null || wl-paste --watch cliphist store &`. The
      watcher never started before because `pgrep -f 'cliphist store'` matches the shell running it
      (the pattern is in its own command line), so it always answered "already running" and the watcher
      was never spawned. `pgrep -x wl-paste` asks about the real process. It lives in
      `hl.on("hyprland.start")`, so it starts with the compositor - after a plain `hyprctl reload` on a
      session that predates it, start it once by hand
- [x] Ctrl+P pins the highlighted entry, pins sort first and survive restarts
- [x] frecency ordering, the entries used most and most recently float up, also across restarts
- [x] file search is debounced, depth limited and skips .cache/.git/node_modules/.local/.cargo so it
      stays usable
- [x] everything it remembers lives in one cache directory inside the config dir,
      `quickshell/cache/launcher` (Quickshell.shellDir + "/cache/launcher", ignored by git through
      `/quickshell/cache` in .gitignore; Quickshell.cacheDir turned out to be a per-instance hash dir
      under ~/.cache that the old guard never mentioned): pins.txt and usage.txt (id, count, last used).
      Verified live: after launching an app from the launcher the file is there,
      cache/launcher/usage.txt with act:Shut down and app:code-insiders in it
- [x] usage.txt is capped at Config.launcherUsageMax (10) entries, the most recently used ones, so the
      file cannot grow without bound (Helpers.formatUsage(usage, max), verified: 12 launcher opens left
      exactly 10 lines, the 10 newest)
- [x] pins round trip: Ctrl+P on a row writes the id to pins.txt and the row shows the pin glyph
      (probe: pinRequested=app:btop -> pins=["app:btop"], the btop++ row reports pinVisible=true and
      pins.txt holds app:btop)
- [x] check.js covers the calculator entry detection (`calcEntry`), the cliphist listing and the rest
- [x] a `Terminal=true` app opens inside the terminal the hyprland config names: the launcher cats
      Config.launcherTerminalConfig (~/.config/hypr/programs.lua, with `~` expanded to $HOME and re-read
      on every open), Helpers.terminalName takes the first `terminal = "..."` line (the table entry in
      programs.lua, the older `local terminal = "..."` form, or the legacy `$terminal = kitty` one) with
      no fallback: whatever the config names is what runs. Verified
      on a scratch shell: the probe reads terminal=footclient for this config and the command is
      `footclient -e sh -c btop`; `-e` is what foot, footclient and alacritty all take. The real bug was
      upstream of that: AppIcons' grep only asked for Name/Icon/StartupWMClass/Exec/NoDisplay/Hidden, so
      `Terminal=true` was never parsed and btop ran bare with no terminal at all. Now grep reads it too,
      and a real `footclient -e sh -c sleep` opens a foot window while `sh -c btop` would not
- [x] the cards are solid, not blurred: there is no `BackgroundEffect` anywhere and Hyprland's
      decoration.blur stays off, so nothing behind any shell surface is sampled. Config.surface is the
      grey (#101010) and Config.surfaceAlpha (1) is the whole transparency knob, so the launcher, the
      bar and the widgets all share it; lower it to make every card see-through again

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
  Hyprland border, gap and animation parsing and the pipewire stream parsing: node lib/check.js
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
- the tooltip is the Tooltip primitive, and since it has to hold the keyboard for the monitor cards
  it is a PanelWindow on the top layer, not a PopupWindow. The one thing that moved with it: a
  layer surface is positioned inside the *usable* area, i.e. below the bar's exclusive zone, while a
  popup was positioned in screen coordinates, so the same margin lands one bar lower (the tooltip sat
  at y99 instead of 53). `hang` is now gaps_out + tooltipOffsetY = 7 below the bar bottom either way,
  and it no longer needs the bar's height in it. Verified from the pixels: the card's border row at
  logical y53.1 and its surface at 54.4, the same place the popup version had it


Make switching workspaces with the mouse wheel faster while holding the SUPER button

## Default actions (last step, not built yet)

One place that says what "open", "edit", "terminal", "file manager", "browser" mean and which keys
move around, so every widget asks the same source instead of each file hardcoding its own command and
its own Qt.Key_*. Nothing here is built yet.

Specs:

- [ ] config.js: a `defaults` block (editor, terminal, fileManager, browser, imageViewer, pager) plus a
      `keys` map for the movements every popup shares: up / down / left / right, next / previous,
      accept / cancel, page up / page down, close
- [ ] helpers.js: `openCommand(kind, path)` returning an argv list instead of a shell string, and
      `keyAction(event, map)` turning a key event into an action name, so a widget names the action
      ("up", "accept") and the map decides the chord
- [ ] Launcher.qml, Calendar.qml, VolumeMixer.qml, Tooltip.qml and the bar take their keys from that
      map instead of hardcoding Keys.onDownPressed / Qt.Key_PageDown / Ctrl+P
- [ ] the editor, file manager and browser come from the desktop's own choice at runtime
      (`xdg-settings get default-web-browser`, `xdg-mime query default inode/directory`) with
      Config.defaults as the override, cached at startup, `xdg-open` as the last resort
- [ ] launcher rows get "edit" and "reveal in file manager" on the `.` (file search) rows, and the
      systemd/log paths on the tooltips where a path makes sense

Contracts:

- the key map renames keys, it is not a macro system: one key, one action, no sequences and no side
  effects, and a widget that needs a key for something else (text entry in the launcher) keeps it
- hypr/hyprland.lua and the files it requires stay the source of truth for global movement (window
  and workspace focus, the mouse wheel binds); this only covers movement inside the shell's own
  surfaces
- resolve each default once at startup and expose it read-only, so a broken `defaults` entry cannot
  make a widget launch something surprising mid session
