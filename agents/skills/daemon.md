# yudaemond

One daemon owns every non-UI job. QML draws, it does not think.

## Rules

- Nothing non-UI in QML: no curl, no Process for data, no JSON parsing, no state machines. If it is not pixels, it belongs in `daemon/`.
- QML consumes state from `shell/services/Yudae.qml` (unix socket, one JSON object per line). Full snapshot, no patch protocol.
- UI follows the same rules as the backend: no file over 1000 lines, split by function, shared pieces become primitives.
- Zig stdlib only. No third-party deps, no cgo, no vendored libs. C/C++ only for the Hyprland cursor plugin.
- Another language is allowed only when it wins on LOC, speed or RAM, and only with the user's explicit yes first.
- Used twice -> primitive, own file (`daemon/src/primitives/`, `shell/ui/`).
- Files over 1000 lines get split by function. A file does one job.
- Tests only where logic breaks silently (parsers, state merge, protocol framing). No test for a getter. No test frameworks, no fixtures.
- No comments in code.
- Never call `hub.publish()` while holding a provider mutex: the snapshot renders that provider and the lock is not reentrant. Unlock, then publish.

## Adding a provider

1. `daemon/src/providers/<name>.zig` with `init`, `render`, and the commands it accepts.
2. Add it to the context in `main.zig`, register its render with the hub, and route its commands in `commandThunk`.
3. Pair it with `shell/features/<name>/`; add or delete both together.
4. Add it to `doctor` if it has a reachability state.

## Performance gates

Measured, not guessed. `scripts/yubuild` prints build time and cache size after every build and prunes the cache over 300MB.

- incremental build under 2s
- cold build under 20s
- binary under 3MB
- start under 10ms (fork to socket ready)
- idle RSS under 8MB
- zero subprocess spawns at steady state

`yudaemond bench` records all of them against `bench/baseline.json`. An optimization that breaks parity does not count. Re-run bench after every change that touches a hot path.

## Agent tools

Never guess a command; these are the entry points:

- `yudaemond --json state` - current state, no QML needed.
- `yudaemond doctor` - per provider reachability and reasons.
- `yudaemond bench --json` - the numbers above, machine readable.
- `yudaemond parity` - old QML vs daemon state comparison.
- `yudaemond mcp` - stdio JSON-RPC server: state, providers, bench, parity, hypr_start, hypr_shot, hypr_run, hypr_stop, qs_log, vm_*.

## Lifecycle

- `systemd/user/yudaemond.service` lives in the repo: `PartOf=graphical-session.target`, `Type=notify`, `Restart=always`.
- Daemon dies -> read the log, fix the root cause, restart. Never revert working daemon code to get a green run.
- Quickshell restart must not require a daemon restart, and the daemon restart must not require a shell restart.
