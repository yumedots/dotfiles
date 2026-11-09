# Plugins

One standard to make, load and share anything that modifies the system: Hyprland plugins, themes, shell features and app configs. A theme is a plugin.

## A plugin is a folder

```
plugins/<id>/
  plugin.toml
  Makefile
  src/ ...
  hypr.lua        hypr only
  theme.toml      theme source, rendered by make
```

`plugins/_template-hypr/`, `_template-theme/`, `_template-shell/`, `_template-app/` and `_template-daemon/` are working examples. Copy one and rename every `_template-*` name.

### Manifest

```toml
id = "drop-preview"
kind = "hypr"
version = "1.0.0"
build = "make"
provides = ["drop-preview.so"]

[requires]
hyprland = ">=0.50"
```

| key | rule |
| --- | --- |
| `id` | folder name, `^_?[a-z][a-z0-9-]*$`; a leading `_` marks a template |
| `kind` | `hypr`, `theme`, `shell`, `app` or `daemon` |
| `version` | free string |
| `requires` | optional; only `hyprland`, with `>=`, `<=`, `>`, `<` or `=` and a dotted version |
| `build` | command run in the folder with `OUT` in the environment; `make` sees `OUT=<dir>` |
| `provides` | relative paths the build must write under `OUT`; no `..`, no absolute paths |

Unknown keys are rejected so a typo never turns into a silently ignored field.

### Source only

No `.so`, `.bin`, `.o`, `.a`, `.dylib`, `.dll`, `.exe` and no ELF file may exist inside a plugin folder. The conformance suite and the loader reject them, so every Hyprland update can rebuild from source. Built files live in `$XDG_STATE_HOME/yudae/build/<id>/`.

Lua, scripts, QML and assets are allowed. Security is the user's call.

## Load list

`$XDG_STATE_HOME/yudae/plugins.toml`, never shipped. `YUDAE_PLUGINS` overrides the path for tests and VMs. A missing file means no plugins and the built-in defaults.

```toml
load = ["tokyo", "borders-plus-plus", "drop-preview"]

[tokyo]
accent = "#7aa2f7"
```

- Order matters; later plugins override earlier ones (theme colors in particular).
- A `[id]` table becomes `YUDAE_PLUGIN.options` in `hypr.lua`.
- A plugin not in `load` is never touched.

Source folders are found in the repo `plugins/` first, then `$XDG_DATA_HOME/yudae/plugins/` for `plugin add`.

## Kinds

One adapter per kind in yudaemond. Plugins never touch the loader.

### hypr

- `provides` has the `.so` or `.bin`. `hypr.lua` contains config only.
- yudaemond writes `$XDG_STATE_HOME/yudae/loaded.lua`; `hypr/hyprland.lua` `dofile`s it after the normal config. The generated file loads each current binary, sets `YUDAE_PLUGIN` (`id`, `dir`, `out`, `options`) and inlines the plugin's `hypr.lua`.
- At daemon start the loader reads `pkg-config --modversion hyprland`. The stamp holds that version and a hash of every source file. A changed version or source rebuilds; `loaded.lua` never compiles.
- A stale plugin is skipped at login, rebuilt by the daemon and loaded live with `hyprctl plugin load`.
- A running Hyprland older than the headers refusing the `.so` is non-fatal; it loads after the next login.
- A failed build skips only that plugin, posts a notification with the compiler output, and keeps the desktop running.

### theme

- `provides` has `theme.toml`. It may use the same sections as `shell/config.toml` (`[colors]`, `[weather]`, `[calendar]`, ...), so a key replaces the base value in its own section. Every key must be a color setting from `shell/services/Config.qml`; values are `#rrggbb` or `#aarrggbb`.
- yudaemond merges themes in load order into `$XDG_STATE_HOME/yudae/theme.toml`.
- `providers/config.zig` reads that file after `shell/config.toml`, so `Yudae.settings` retints live without a shell restart.

### shell

- `provides` includes the QML entry. The first `.qml` in `provides` is the entry.
- yudaemond exposes every loaded shell plugin in the `plugins` snapshot with a `file://` entry URL.
- `shell/PluginHost.qml` instantiates each entry. The entry is a Quickshell surface (`PanelWindow`), not a plain item.
- The suite lints every `.qml` in the folder with `qmllint`.

### app

- `build` renders the template into `$XDG_STATE_HOME/yudae/build/<id>/`; every `provides` path must exist afterwards.
- Nothing is installed into `~/.config`; the app reads the rendered file from the state dir.

Example: `plugins/foot/theme.ini` renders to `~/.local/state/yudae/build/foot/theme.ini`.

### daemon

A compile-time provider. The loader still validates and builds its manifest, but the provider list in yudaemond decides what runs.

## Commands

```
yudae plugin list
yudae plugin build <id>
yudae plugin load <id>
yudae plugin unload <id>
yudae plugin add <git-url>
yudae plugin update <id>
yudae plugin reload
```

- `load` and `unload` edit the TOML and reload immediately.
- `build` forces one build, then reloads the generated Lua and live-loads Hyprland plugins.
- `add` clones into `$XDG_DATA_HOME/yudae/plugins/<manifest id>`, records the commit in `$XDG_STATE_HOME/yudae/commits/<id>`, adds it to `load` and reloads. It prints kind, version, commit and path.
- `update` pulls an installed plugin, records the commit and reloads. Repository plugins are not pulled.
- `reload` re-reads the list, rebuilds stale plugins, rewrites `loaded.lua`, merges themes and applies shell/app plugins.

## Tests

- `scripts/plugin-check` (the `checks/plugins` test in `xmake test`) discovers every `plugins/*`, validates the manifest, rejects binaries, runs `make`, checks `provides`, lints shell QML, parses theme colors and builds app templates.
- Zig unit tests cover the load list, missing folder, broken TOML, unknown kind, duplicate id, requires mismatch, order, options, unload, source hash, theme layering and a real Hyprland template build.
- VM scenarios `vm/scenarios/plugin-*.json` cover no list, load, unload, stale source, broken source, binary in folder, missing compiler, themes, theme layering, Lua themes, shell, app and Hyprland.

Golden images can be pinned to an Arch Linux Archive date:

```
xmake vm packages --snapshot 2026/10/28
xmake vm golden --snapshot 2026/10/28
yudae vm create old --from 2026-10-28
```

`--from` accepts a VM name (clone its disk) or a golden tag built by `vm/images`.
