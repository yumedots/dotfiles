---
name: yudaemond
description: Use when editing the Zig daemon, adding a provider, changing IPC, snapshots, commands or daemon performance.
---

Read `agents/skills/daemon.md` and `docs/daemon.md` from the repo root first.

- One provider per feature; register the target in the provider and keep the snapshot contract.
- Reuse the primitives in `daemon/src/primitives/`; do not add a dependency for something the standard library covers.
- Add or update the parser/protocol test next to the code.
- Run `zig build test` and `zig build -Drelease=true` before reporting.
