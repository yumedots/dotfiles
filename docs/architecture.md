# Architecture

TLDR: one repo, split by what a thing is. xmake is the single entry point. `vm` runs disposable KVM machines for real-session tests. One IPC door for commands.

## Layout

```
dotfiles/
  config/            plain app configs, one dir per app, each symlinked to ~/.config/<name>
  hypr/              hyprland conf + cursor plugin (C++); the one non-config symlinked, hyprland reads ~/.config/hypr
  shell/             quickshell, run with `quickshell -p`, never symlinked
    features/<name>/ one folder per feature: Card.qml Widget.qml Service.qml feature.json
    ui/              primitives used twice or more
    lib/ greeter/ lock/ launcher/
  daemon/            yudaemond (Zig); src/providers/<name>.zig pairs with features/<name>
  systemd/ scripts/
  vm/                images, overlays, qemu command builder, scenarios
  docs/              reference: how the system is shaped
  agents/skills/     task guides: how to do X
  xmake.lua + one xmake.lua per dir
  plans.md AGENTS.md README.md
```

## Rules

- A feature has one name. `features/weather/` on the QML side, `providers/weather.zig` on the daemon side. Add or delete both together.
- `config/` has no code. Anything with logic leaves it.
- `AGENTS.md` is an index. Procedure goes in `agents/skills/`, reference in `docs/`.
- Only `xmake link` writes into `~/.config`. It refuses to overwrite a real file and prints what it would replace.
- The shell and greeter run from the repo path, never from `~/.config`.

## xmake

xmake orchestrates, it does not replace the real builders.

| task | does |
| --- | --- |
| `xmake build` | daemon (wraps `zig build`), cursor plugin (native C++ target) |
| `xmake link` | symlink `config/*` and `hypr/` into `~/.config` |
| `xmake lint` | qmllint on `shell/`, `node shell/lib/check.js` |
| `xmake test` | daemon parsers/protocol tests, qml fixtures, idle-spawn test |
| `xmake bench` | headless daemon cold build, size, start, idle RSS and spawns, then `yudaemond bench` against `bench/baseline.json` |
| `scripts/vm-test` | VM UI loop (start, restart, shot, run); `xmake hypr` is the quick nested loop |
| `xmake vm ...` | VM images and bench; running VMs are `yudae vm` |
| `xmake doctor` | what is missing and why |

`zig build` stays underneath: the build budgets are measured on it and `scripts/yubuild` reports them. `zig build -Dheadless=true` builds `yudaemond-headless`, the minimal control-plane daemon that carries the performance gates.

`scripts/xmake` is linked to `~/.local/bin/xmake`. Inside the repo it dispatches `link`, `lint`, `bench`, `hypr`, `vm` and `doctor` to `scripts/tasks.sh`; every other xmake command goes to the system xmake.
