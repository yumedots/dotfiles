# yudaemond

The shell backend. One Zig process, no dependencies.

- `zig build -Drelease=true` builds `zig-out/bin/yudaemond`
- `../scripts/yubuild` builds, times it, and prunes the cache
- `yudaemond state`, `doctor`, `bench`, `bench widgets`, `parity`, `mcp`
- `yudaemond bench widgets` ranks every shell widget by open time and by shell
  and daemon RSS/CPU while it is open, measured in the nested `hypr-test`
  session, and stores the raw run under `bench/widgets/<timestamp>.json`
  (`--json` prints it, `--widgets id[,id]` narrows the run, `--hold` seconds)
- The systemd unit lives at `~/.config/systemd/user/yudaemond.service`
- QML talks to it through `quickshell/services/Yudae.qml`

Everything not on screen belongs here. The files under `src/providers/` each
own one source of state; `src/primitives/` holds the pieces used more than once.
