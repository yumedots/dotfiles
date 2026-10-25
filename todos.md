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
- `7ceaa21` volume widget reads the sink from the daemon (it was erroring on a
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

1. **Launcher port (paused by the user)**: `quickshell/yudaemond/src/providers/launcher.zig`
   exists and runs, wired in `main.zig` (`launcher` command group) and `tests.zig`,
   and `Yudae.qml` does not use it yet, `Launcher.qml` is untouched.
   - daemon side present: modes/groups/saved/apps/rank/usage/pins/clipboard
     list+preview+copy/procs/kill, snapshot key `launcher`
     (`mode`, `prompt`, `query`, `terminal`, `pins`, `results`, `clip{text,path}`).
   - still to do: QML rewrite of `Launcher.qml` (1079 lines, must go under 1000)
     to consume `Yudae.launcher` and send `{cmd:{launcher:{query,forced,group}}}`,
     `pin`, `save`, `remember`, `clips`, `clip`, `copyClip`, `kill`; window
     switcher stays on Hyprland toplevels; drop `lib/apps.js`/`entries.js`/
     `parse.js` leftovers once nothing uses them.
   - tests still missing: launcher pins/usage round trip through the files.
4. Not started: nothing else. `Root.qml` has no backend data left (only the
   qmldir hot-reload FileView and Hyprland events).

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
