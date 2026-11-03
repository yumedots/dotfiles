# Agent tooling

Everything an agent needs is a CLI or an MCP tool. Never guess a command.

## CLI

```
yudae call <target> <method> [args...]     # -q: quiet no-op if nothing is running
yudae state | doctor | bench | parity | ui tree
yudae vm <verb> ...                        # same verbs as the MCP tools
```

- The daemon owns routing. A feature registers its target in its provider (`weather`, `launcher`, `bar`, `menu`, `lock`, `vms`).
- Hyprland binds, scripts, the MCP and VM scenarios use `yudae call`, never raw `qs ipc call`.
- Changing state from a CLI pushes a refresh; no timers.
- The same command works inside a VM, because the guest runs the same yudaemond.

## MCP

`yudaemond mcp` is a stdio JSON-RPC server.

- state, providers, bench, parity
- hypr_start, hypr_shot, hypr_run, hypr_stop, qs_log
- vm_create, vm_list, vm_state, vm_exec, vm_push, vm_pull, vm_key, vm_type, vm_click, vm_move, vm_screenshot, vm_wait, vm_sleep, vm_wake, vm_park, vm_destroy, vm_snapshot, vm_restore, vm_fork, vm_view, vm_ui_tree, vm_run_scenario

Every result is bounded and typed: capped output with a handle for the rest, exit codes, durations.

## VM workflow

Structured state first, pixels last:

1. `vm_state` - the guest daemon snapshot.
2. `vm_exec` / `vm_ui_tree` - text and tree.
3. `vm_screenshot` - visuals only.
4. `vm_wait` - QMP events, Hyprland events and the guest socket. No sleep loops, no screenshot spam.

A human can watch and take over with `vm view <name>`. While a human holds input, agent input fails with "human has control".
