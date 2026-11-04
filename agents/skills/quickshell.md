# Quickshell

## Run and reload

- Saving a file live-reloads the running quickshell. Never restart it for a normal edit and never run a second instance.
- The shell runs from the repo with `quickshell -p shell/shell.qml`. Nothing the shell runs lives in `~/.config` except the symlinks `xmake link` makes.
- The greeter runs the same tracked shell as the user session. Never copy QML, scripts or config into `/etc` or `/usr`; system files (greetd, systemd drop-ins, polkit) may only point at the repo.

## Surfaces

A surface that is not on screen is unmapped, and nothing inside it runs: no canvas, no timers, no repaint. A bar widget gates animation on the bar's `onScreen`; a window unmaps when it slides or fades away, or when the lock hides it. Never keep a hidden surface mapped.

## Data

QML draws, it does not think. No curl, no Process for data, no JSON parsing, no state machines. Read the snapshot from `services/Yudae.qml`; send commands with `yudae call`.

## Lint

```
ln -sfn <repo>/shell /tmp/qmlimport/qs
/usr/lib/qt6/bin/qmllint -I /tmp/qmlimport <files>
```

Exit 255 means a syntax error; quickshell dialect warnings are noise. `lib/*.js` changes: `node shell/lib/check.js`.

## Logs

`/run/user/1000/quickshell/by-id/<newest>/log.qslog` (use `grep -a`).

## Verify

Visual changes are not done until seen through `scripts/vm-test` (start, restart, shot).
