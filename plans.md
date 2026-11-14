# Plans

## 1. Plugins

One standard to make, load and share anything that modifies the system: Hyprland plugins, themes, shell features, app configs. Themes are plugins.

### A plugin is a folder

```
plugins/<id>/
  plugin.toml     id, kind, version, requires, build, provides
  Makefile        build instructions: make OUT=<dir> writes the files in provides
  src/ ...        source
```

- Source only. No `.so`, `.bin`, `.o` or ELF file inside a plugin folder; the loader and the suite reject them so a Hyprland update can always rebuild.
- Built files go to `~/.local/state/yudae/build/<id>/`, never into the plugin folder.
- A plugin may ship anything else, Lua and scripts included. Security is the user's call; nothing else is rejected.
- `drop-preview.so` is tracked in git today; it needs `git rm --cached` and a `.gitignore` entry when the user says commit.

### The load list

`~/.local/state/yudae/plugins.toml`, never shipped. `YUDAE_PLUGINS` overrides the path for tests and VMs.

```toml
load = ["tokyo", "borders-plus-plus", "drop-preview"]

[tokyo]
accent = "#7aa2f7"
```

- A plugin not in `load` is never touched. Order matters; later plugins override earlier ones.
- A `[id]` table passes options to that plugin.
- A missing file means no plugins and the built-in defaults.

### Kinds

Each kind has one adapter in yudaemond. A new kind is one adapter; plugins never touch the loader.

| kind | loading does |
| --- | --- |
| `hypr` | daemon writes `loaded.lua` with `hl.plugin.load` and the plugin's `hypr.lua`; `hypr/hyprland.lua` `dofile`s it, replacing `hypr/plugins.lua` |
| `theme` | merges its colors into `Yudae.settings`; the shell retints live |
| `shell` | the shell instantiates its QML feature |
| `app` | renders a template into the state dir (foot, gtk, ...) |
| `daemon` | a provider; compile-time list first |

### Building on Hyprland updates

- At start yudaemond reads `pkg-config --modversion hyprland`. Each plugin's stamp holds that version and the source hash. A different version, older or newer, runs `make` for every loaded `hypr` plugin. No package hooks; nothing is installed.
- Missing compiler or headers: report what is missing.
- A failed build means that plugin is not loaded, a notification is shown, the others still load.
- `loaded.lua` only loads binaries with a current stamp and never compiles. A stale plugin is skipped at login, rebuilt by the daemon and loaded live with `hyprctl plugin load`.
- A running Hyprland older than the installed headers refuses the `.so`; that is non-fatal and the plugin loads after the next login.

### Commands

`yudae plugin list | build <id> | load <id> | unload <id> | add <git-url> | update <id> | reload`. `load` and `unload` edit the TOML and reload immediately. `add` clones into `$XDG_DATA_HOME/yudae/plugins/<id>`, prints what it contains (kind, Makefile, Lua, scripts) and installs without a prompt, recording the commit.

### Tests

- Zig unit tests for the loader: empty list, missing folder, bad TOML, unknown kind, duplicate id, `requires` mismatch, order, override conflict, unload.
- A conformance suite in `xmake test` that discovers every `plugins/*` and checks it by kind: valid manifest, `make` succeeds, `provides` exist, no binaries, theme color keys, `app` templates render, `shell` passes `qmllint`, `hypr` loads.
- VM scenarios `vm/scenarios/plugin-*.json`: no `plugins.toml`, load and unload a `hypr` plugin, stale stamp, broken source, binary in the folder, missing compiler, theme load, theme layering, theme with Lua, one real `shell` plugin, one real `app` plugin.
- Extra golden images for a real Hyprland change: `old` built from a dated Arch Linux Archive snapshot (the whole system, since Hyprland needs matching `hyprutils` and `aquamarine`), the current one, and a newer one if needed. Selected by a flag on `xmake vm packages`, started with `yudae vm create --from`. Scenarios: upgrade, downgrade, same version (no-op), stale headers. The faked-stamp scenario stays as the fast smoke test.

### Agents first

- Skill in `.agents/skills/plugin/SKILL.md` with frontmatter and a few rules; the reference is `docs/plugins.md`.
- `plugins/_template-<kind>/`: one minimal working example per kind that passes the suite; an agent copies one.
- The `yudae plugin` verbs are MCP tools.
- `docs/plugins.md` comes after, written from the templates; `docs/architecture.md` and `docs/agent-tooling.md` updated.

### Order of work

1. Manifest spec, conformance suite, the two-file skill, the "no `plugins.toml`" scenario.
2. `_template-hypr` and `_template-theme`.
3. The loader in yudaemond.
4. The `hypr` adapter: replace `hypr/plugins.lua`, move the three plugins to `plugins/<id>/`, move their config (`plugins.lua`, `hypr/drop-preview.lua`) into each `hypr.lua`. Nothing moves before the loader exists.
5. The `theme` adapter with one real theme.
6. The extra VM images and the full end-to-end suite.
7. MCP tools, `docs/plugins.md`, `add` and `update`, then the `shell` and `app` kinds.

Settled: state dir is `~/.local/state/yudae`; source only; version check at daemon start, no package hooks; nothing is rejected but binaries; everything tested end to end in the VM; agents first.
