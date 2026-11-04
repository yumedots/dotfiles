---
name: VM
description: Use when working with the QEMU VM control plane, guest scenarios, the VM viewer app, yudae VM verbs, or the yudae MCP VM tools.
---

Read `agents/skills/vm.md` from the repo root for the full VM lifecycle and commands.

- Drive the VM through `yudae` or the yudae MCP (`opencode mcp list` -> yudae). Do not write throwaway scripts for VM actions.
- If the daemon lacks the action, ask the user before adding it to yudaemond.
- The viewer app runs on the host. Test guest UI inside the VM with `scripts/vm-test` or `yudae open <vm> <app>`.
- Read `agents/skills/vm.md`, `docs/agent-tooling.md` and `docs/daemon.md` before changing VM behavior.
