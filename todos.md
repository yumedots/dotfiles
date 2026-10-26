# todos

State as of the yudaemond port. Branch `yudaemond`, repo `/home/gabriel/.config`.

## Where we left off

Done and committed:

- `9ef3901` mixer reads the daemon: `audio.zig` emits nodes (props, volume, mute,
  isStream, isSink, ready, running, description) plus `sink`/`source`/`hasInput`;
  `VolumeMixer.qml` binds it, its `pw-dump` Request and PwObjectTrackers are gone.
- `99df736` app list keeps one entry per id (duplicate `.desktop` ids broke the
  state JSON for `doctor`/`mcp`).
- `cd20db8` hypr request frees what it owns (`proc.env` now caches `/proc/self/environ`
  and hands out borrowed slices; the daemon was crash-looping on an invalid free).
- `99065db` network panel: daemon owns the speed test and the DNS edit, wifi list
  bound to `Yudae.network.wifi`, dead `network.js`/config pruned.
- `d27da0b` wallpaper picker and bar layout read the daemon (`wallpaper.zig`,
  `bar.zig`); wallpaper apply (`awww img`) is code-reviewed only, never run from
  the daemon because it hits the real desktop.
- `89a223c` `primitives/calc.zig` + `apps.view()` + desktop recursion test.
- `598fea3` mixer shows real volume (channelVolumes cube root) and follows
  `pactl subscribe`; app icons refresh through a live binding.
- `7ceaa21` volume widget reads the sink from the daemon
- mixer: real volume (cube root of channelVolumes), event-driven updates (35-57 ms),
  one publish per change, drag mapped in card space with a jump filter, wpctl writes
  queued off the client thread, two daemon crashes fixed (ipc use-after-free,
  launcher arena) - `4b9a3fd f8ab1bb 317c72a 873c9e1 e4dc988`
- icons: one resolver in the daemon (`primitives/icons.zig` + `providers/icons.zig`,
  `icons` snapshot section) used by `AppIcons.qml` for the mixer, launcher, window
  switcher, notifications and tray; case-insensitive desktop ids + category fallback
  - `23d0eb7 298f495 a943184`
- weather: the inline place editor commits the matched suggestion, needs 3 letters,
  ranks by population, keeps the card visible, suggestions live in the card -
  `304555f 43b68fc 10e0fba 5a86b41` (it was erroring on a
  missing `import qs.services`, so no OSD and no icon change).

## Done since this file was written

- Latency: 168 ms -> 35-57 ms. The pactl event thread samples itself (serialized
  by `sample_mutex`) and a `change` event on an audio object patches that node
  with `wpctl get-volume` instead of a 25 ms `pw-dump`. Idle CPU 6.1% -> 1.4%.
- Fader drag: three separate bugs. Rows reflowed mid-drag so the fader got
  coordinates from another layout (values slammed to 0/1); the stream rows were
  rebuilt on every snapshot (the pressed MouseArea died); every drag message ran
  `wpctl` on the client's socket thread. Fixed by persisting delegates
  (`model: nodes.length`), pinning a drag to the size it started with, ignoring
  out-of-range positions, and a coalescing write queue on a worker thread.
  Verified with ydotool: 0.95 -> 0.30 tracked 0.8,0.7,0.6,0.5,0.4,0.3, final
  exactly the pointer position.
- Volume widget (`VolumeStat`) beside the OSD was missing `import qs.services`,
  so it errored and never updated; it now binds straight to `Yudae.audio`.
- `ydotool` is installed and working. Coordinates: `hyprctl cursorpos` shows
  logical pixels and `ydotool mousemove --absolute X Y` takes X/2, Y/2.
  `click 0x40` = left down, `0x80` = left up, `0xC0` = full click.

## Open

0. ~~**Ink and awww belong to the daemon.**~~ done: `5298b12` (daemon) + `c985c82` (QML).
   `providers/ink.zig` owns `bar-ink.json`, the band/bare command, the `awww` apply and its
   supervision, and samples the ink from the cached 1280px preview (ffmpeg crop of the top
   band, mean colour blended toward white/black). `BarInk.qml` is 186 -> 64 lines with no
   Process, FileView or writes, same public API. Live: `{"bare":true,"band":33,"inks":{"DP-2":"#3a280a"}}`.
   Original note: `quickshell/services/BarInk.qml` still does the ink
   work in QML: it measures the bar height, passes `--ink-band` to `awww img`, samples the
   wallpaper's colours, persists `cache/bar-ink.json`, and runs its own Processes. We own
   both ends (the daemon, and awww which lives under `~/`), so the daemon should: keep the
   band height (the bar reports its height once as a number), spawn and supervise `awww`
   (apply a wallpaper, keep the daemon alive, expose its state), compute the ink colours
   from the rendered wallpaper preview it already caches (no second decode), persist the
   bar-ink state itself, and publish `ink` in the snapshot. Then `BarInk.qml` shrinks to a
   read-only view of that section and loses every Process/FileView.

1. **Process pairing (launcher <-> shell), owned by the daemon.** The launcher is a separate
   `quickshell -p launcherShell.qml` process (kept apart for tearing reasons). Today nothing
   watches the pair: kill the shell and the launcher lingers; kill the launcher and the shell
   keeps a dead IPC target. Wanted: `providers/supervisor.zig` that finds both pids
   (`comm == quickshell`; the launcher by `cmdline` containing `launcherShell.qml`), polls
   every 2 s, and when one disappears sends SIGTERM to the other (and restarts the launcher
   when the shell is alive but the launcher is gone). Also useful: expose both states in the
   snapshot (`supervisor: { shell, launcher }`) so the QML can warn instead of silently
   talking to nothing. Keep it process-based, no subprocess per second beyond the poll.


2. **Launcher QML** (the only real port left). `quickshell/yudaemond/src/providers/launcher.zig`
   is written, wired and tested (`111eeaa`) and emits the `launcher` snapshot section
   (`mode`, `prompt`, `query`, `terminal`, `pins`, `results`, `clip{text,path}`), but
   `quickshell/launcher/Launcher.qml` (1089 lines, over the 1000 rule) still uses
   `lib/apps.js`, `lib/entries.js` and `lib/parse.js` and never reads `Yudae.launcher`.
   To finish: bind the rows to `Yudae.launcher.results`, send
   `{cmd:{launcher:{query,forced,group}}}` on every keystroke/mode change, plus
   `pin`, `save`, `remember`, `clips`, `clip`, `copyClip`, `kill`; keep the window
   switcher on Hyprland toplevels; split the file under 1000 lines; then delete the
   JS left-overs.
3. **Launcher tests**: pins/usage round trip through `cache/launcher/*.txt`.
4. **Wallpaper apply never executed.** The picker, scan, thumbnails, keyboard and
   the saved-settings write are done and verified; `awww img --ink-band` is only
   code-reviewed because it would change the real wallpaper from the systemd daemon.
   Test it once in a real session (pick a wallpaper, check the desktop + settings.lua).
5. ~~**Display rapid changes.**~~ done: `467e556` - one apply worker owns every
   `hyprctl eval`, picks land in a single-slot queue (newest replaces the waiting one),
   `panel.pending` is true while a change is in flight and the panel shows the queued
   value. Verified with two mouse clicks 300 ms apart (60 Hz then 240 Hz, both applied
   in order); the user's 279.96 Hz / 1.3333 scale and `display.lua` were restored byte
   for byte. Original note: A single scale/refresh change applies in ~250 ms
   via `hyprctl eval hl.monitor(...)`, and the panel now shows the value it applied.
   Two changes within ~1 s still lose the second one while the mode switch is in
   flight. Needs a pending flag in the panel that ignores a second pick until the
   first lands (or a queue in `screen.zig`).

## Verify each port

```
cd quickshell/yudaemond && zig build test        # 48 tests
zig build && systemctl --user restart yudaemond
yudaemond state | jq .launcher                   # whatever you touched
yudaemond parity
ln -sfn ~/.config/quickshell /tmp/qmlimport/qs
/usr/lib/qt6/bin/qmllint -I /tmp/qmlimport <files>   # exit 0, unqualified warnings are noise
scripts/hypr-test start|shot|run|stop            # worktree copy: restart after every edit
```

## Gotchas that cost time

- `hypr-test` copies the tree at start: edits after `start` are invisible to the
  nested session. Always restart the instance after editing QML, or verify in the
  real session.
- A QML file missing `import qs.services` silently kills the widget (`Yudae is
  not defined`) - check the instance log, not the screenshot.
- `std.Io.Reader.readSliceShort` blocks until the buffer is full; stream with
  `readVec` or `poll`+`read`.
- Never `hub.publish()` under a provider mutex; `sample()` must unlock first.
- `quickshell/cache/launcher/*.txt` are the launcher's state files (pins, usage,
  saved), written with `{id}\t{count}\t{last}` / `name\tcommand`.
