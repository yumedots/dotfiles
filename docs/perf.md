# Performance

Measured, not guessed.

## Budgets

| gate | budget |
| --- | --- |
| incremental build | under 2s |
| cold build | under 20s |
| binary | under 3MB |
| start, fork to socket ready | under 10ms |
| idle RSS | under 8MB |
| subprocess spawns at steady state | zero |

The gates are measured on the headless daemon, `zig build -Drelease=true -Dheadless=true`, binary `yudaemond-headless`. That is the control-plane build used by CI and by tests that do not need the QML providers. The full desktop daemon is measured separately and reported by `xmake bench` as information, because it carries the launcher index, icon cache and every UI provider.

## Tools

- `scripts/yubuild` wraps `zig build -Drelease=true`, prints build time and build-folder size, records `bench/build.jsonl`, and prunes the local cache over 300MB.
- `yudaemond bench` records binary size, start time, idle RSS, idle CPU over 60s, shell total RSS, and the top RAM/CPU hoggers with deltas against `bench/baseline.json`.
- `xmake build` and `xmake bench` call the same tools and report the same numbers. Compilation is not reimplemented in Lua.
- `xmake bench` builds the headless daemon with a clean cache, starts it on a temporary runtime dir, measures it, and exits nonzero if a gate fails.

## Measured 2026-11-02

Host: CachyOS, kernel 7.3.1, Zig 0.17.0.

| gate | headless | full desktop daemon |
| --- | --- | --- |
| incremental build | 132-198ms | same build |
| cold build | 9.1s | 80s |
| binary | 360KB | 2.70MB |
| start | 0-1ms | 4ms |
| idle RSS | 3.6MB | 41.6MB |
| steady-state spawns | 0 | 0 |

The full desktop daemon over the 8MB RSS and 20s cold gates is not a regression hidden by the headless pass: `xmake bench` prints both numbers. The headless build is the profile that meets the budgets.

## Rules

- An optimization that breaks parity does not count.
- Re-run bench after every change that touches a hot path.
- A deliberate simplification with a known ceiling gets a `ponytail:` comment naming the ceiling and the upgrade path.
