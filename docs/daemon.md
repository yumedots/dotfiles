# Daemon shape

`daemon/` is one process, `yudaemond`. It owns every non-UI job: agent state, sessions, plans, workspaces, tray, audio, network, wallpaper, launcher index, icons, and the VM control plane.

## State flow

```
providers -> hub.snapshot() -> unix socket -> services/Yudae.qml -> QML
```

- Each provider renders one key of the snapshot.
- `hub.publish()` coalesces a burst of events into one render (16ms gap) and drops a render identical to the last one.
- The IPC server sends the full snapshot to every client, one JSON object per line. There is no patch protocol.
- `sync` asks for a snapshot after the commands in the same connection, so a caller always sees its own write.

## IPC messages

- `{"sync":true}` - reply with the current snapshot.
- `{"cmd":{...}}` - a command, routed by `commandThunk` in `main.zig`.
- `{"dismiss":"id"}` - dismiss a notification or session row.
- `{"refresh":true}` - re-read provider state.
- `{"gaze":true}` - subscribe to pointer lines for the face.

## Layout

- `src/main.zig` - context, provider wiring, command routing.
- `src/hub.zig` - snapshot render, revision, publish coalescing.
- `src/ipc.zig` - socket server, clients, broadcast.
- `src/cli.zig` - `state`, `doctor`, `bench`, `parity`, `call`, `mcp`.
- `src/mcp.zig` - stdio JSON-RPC tools.
- `src/providers/<name>.zig` - one job each.
- `src/primitives/` - code used twice.

## Command routing

A provider registers its commands by key. `yudae call <target> <method> [args...]` sends `{"cmd":{"<target>":{"<method>":<value>}}}`. With no arg the value is `true`, one arg is a string (or JSON if it parses), several are an array. The daemon routes the target to the provider; the provider validates the method.

## VM control plane

The daemon is the only process that talks to QEMU and to guest daemons:

```
host yudaemond --QMP unix socket--> qemu per VM (screendump, input, stop/cont, balloon)
      |
      +--vsock (CID per VM)--> guest yudaemond (state, ui tree, call, exec)
```

Provider code lives in `src/providers/vms/`: `qmp.zig`, `vsock.zig`, `budget.zig`, `tiers.zig`, `cgroup.zig`, `images.zig`. The snapshot has a `vms` section that QML renders like any other provider. Agents never talk to QEMU or the guest directly.

A governor loop every 5s steps idle VMs hot to warm (5 min), warm to parked (15 min), parked to off (60 min, disk kept). Past the idle destroy budget (default 24h, `YUDAE_VM_IDLE_DESTROY_MS`) it removes the VM and deletes its run dir. Scenario runs delete their VM on success and keep their screenshots.
