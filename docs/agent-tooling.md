# Agent tooling

Everything an agent needs is a CLI or an MCP tool. Never guess a command.

## CLI

```
yudae call <target> <method> [args...]     # -q: quiet no-op if nothing is running
yudae state | doctor | bench | parity | ui tree
yudae plugin list | build <id> | load <id> | unload <id> | theme <id> | add <url> | update <id> | reload
yudae vm <verb> ...                        # same verbs as the MCP tools
yudae open <vm> [app]                      # open the viewer, or an app inside the guest
```

- The daemon owns routing. A feature registers its target in its provider (`weather`, `launcher`, `bar`, `menu`, `lock`, `vms`).
- Hyprland binds, scripts, the MCP and VM scenarios use `yudae call`, never raw `qs ipc call`.
- Changing state from a CLI pushes a refresh; no timers.
- The same command works inside a VM, because the guest runs the same yudaemond.
- `yudae vm key <vm> XF86AudioRaiseVolume` takes hardware names as well as qcodes, so the compositor binds fire. `--hold <ms>` holds the key down for key repeat.

## MCP

`yudaemond mcp` is a stdio JSON-RPC server.

- state, providers, bench, parity
- qs_log
- plugin_list, plugin_build, plugin_load, plugin_unload, plugin_theme, plugin_add, plugin_update, plugin_reload
- vm_create, vm_list, vm_state, vm_exec, vm_push, vm_pull, vm_key, vm_type, vm_click, vm_move, vm_scroll, vm_gui, vm_config, vm_screenshot, vm_wait, vm_sleep, vm_wake, vm_park, vm_stop, vm_destroy, vm_snapshot, vm_restore, vm_fork, vm_view, vm_ui_tree, vm_run_scenario

Every result is bounded and typed: capped output with a handle for the rest, exit codes, durations.

`vm_key` maps hardware names to the QEMU qcode the guest sees, and `hold` keeps the key down in milliseconds for key repeat. Names QEMU has no qcode for (brightness, mic mute) are rejected.

## VM workflow

Structured state first, pixels last:

1. `vm_state` - the guest daemon snapshot.
2. `vm_exec` / `vm_ui_tree` - text and tree.
3. `vm_screenshot` - visuals only.
4. `vm_wait` - QMP events, Hyprland events and the guest socket. No sleep loops, no screenshot spam.

`vm_create` with no name uses the caller's session id as the VM name, so each agent session gets its own VM and a second create reuses it. Idle VMs step down hot to warm at 5 minutes, warm to parked at 15, parked to off at 60 with the disk kept. A VM idle past `YUDAE_VM_IDLE_DESTROY_MS` (default 24h, `0` disables) is destroyed with its disk; `destroyIdleMs` on create overrides it per VM. A scenario destroys its VM when it passes and keeps screenshots in `vm/runs/shots/<name>/`; `"keep": true` in the scenario context keeps the VM for debugging.

`yudae vm scenario shell-ready` is the UI smoke: boot, Hyprland, Quickshell, screenshot.

A human can watch and take over with `vm view <name>` (the Quickshell `vms` app on that VM, 2560x1440 at scale 1.6667) or from the launcher's Virtual machines entry, which opens the app gallery. The gallery shows gray last-viewed thumbnails and renders no VM until a card is clicked. While a human holds input, agent input fails with "human has control". Closing the window or `vm release <name>` returns the guest to 1536x864 at scale 1 for agents and captures a new thumbnail.
