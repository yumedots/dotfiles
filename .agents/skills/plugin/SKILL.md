---
name: Plugin
description: Use when adding, changing or debugging a plugin under plugins/, its manifest, build, load list, theme or hypr.lua.
---

Read `agents/skills/plugin.md` from the repo root first.

- One folder per plugin, source only; `make OUT=<dir>` writes exactly the `provides` paths.
- Copy `plugins/_template-hypr/`, `_template-theme/`, `_template-shell/`, `_template-app/` or `_template-daemon/`; rename every `_template-*` name.
- Never put a `.so`, `.bin`, `.o` or ELF file in `plugins/`; the suite rejects it.
- Config for a plugin lives in its folder, not in `hypr/*.lua`.
- Run `scripts/plugin-check` after every change; it is the `checks/plugins` test in `xmake test`.
- Prove real loading in a VM scenario, not on the host.
