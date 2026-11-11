---
name: VM
description: Use when working with the QEMU VM control plane, guest scenarios, the VM viewer app, yudae VM verbs, or the yudae MCP VM tools.
---

- Drive the VM through `yudae` or the yudae MCP (`opencode mcp list` -> yudae). Do not write throwaway scripts for VM actions.
- If the daemon lacks the action, ask the user before adding it to yudaemond.
- The viewer app runs on the host. Test guest UI with `yudae vm start/exec/screenshot` or a scenario; watch it with `yudae open <vm> <app>`.
- Read `docs/agent-tooling.md` and `docs/daemon.md` before changing VM behavior.
