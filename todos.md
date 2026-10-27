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

1. **Launcher leftovers** (three agents on the visible ones):
   - icons flash the nerdfont fallback before the real icon (`IconInstant`);
   - the Processes tab may be a capped top-N rather than every process, and clipboard
     images never paint although `clip.path` and the file are correct (`ClipProcess`);
   - the Wallpaper entry in the launcher's mode list does nothing when clicked - the
     `openWallpaper()` ipc handoff needs verifying.
2. **Ink cache per wallpaper** (`InkCache`): a verdict per file+band under `cache/`, warm
   switch under 50 ms, invalidated on mtime/size change, precomputed for the scanned list.
3. **Wallpaper apply end-to-end** needs a desktop session to confirm the fade and the
   picker path after the ink rework.
4. **`Parse.plainText`** decision: the last QML-side HTML remover for notification bodies and
   weather text; either move it into the daemon or delete it.
5. **todos.md review**: items 0/1/2 above are done (windows wired `662f041`, launcher <-> shell
   coupling `57339c6`, launcher bound to the daemon `b811ff8`+`daec?`), kept here only as
   history.

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
