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

## Tools

- `scripts/yubuild` wraps `zig build -Drelease=true`, prints build time and build-folder size, records `bench/build.jsonl`, and prunes the local cache over 300MB.
- `yudaemond bench` records binary size, start time, idle RSS, idle CPU over 60s, shell total RSS, and the top RAM/CPU hoggers with deltas against `bench/baseline.json`.
- `xmake build` and `xmake bench` call the same tools and report the same numbers. Compilation is not reimplemented in Lua.

## Measured 2026-11-02

Host: CachyOS, kernel 7.3.1, Zig 0.17.0, release build with LLVM.

| gate | measured | verdict |
| --- | --- | --- |
| incremental build | 132ms | pass |
| cold build, release | 80s | **fail**, budget 20s |
| cold build, ReleaseSmall | 48s, 1.4MB | fail on time |
| cold build, self-hosted `-Dllvm=false` | 4.2s, 19.5MB (7.8MB stripped) | fail on size |
| binary | 2.70MB | pass |
| start | 4ms | pass |
| idle RSS, full daemon | 40.4MB (`RssAnon` 33.7MB) | **fail**, budget 8MB |
| steady-state spawns | 0 | pass |

The two misses are known and not hidden by `xmake bench`, which exits nonzero:

- **Cold build.** LLVM produces the 2.7MB release binary in 80s. ReleaseSmall cuts that to 48s and 1.4MB, still over 20s. The self-hosted backend meets the time at 4.2s but produces a 19.5MB binary (7.8MB stripped), over the 3MB budget. A headless build with fewer providers is the next lever; it is not in this tree yet.
- **Idle RSS.** The full daemon holds the launcher index, icon cache, provider strings and the VM provider. The baseline before the VM work was already 36MB, so this is not a VM regression. Getting to 8MB needs a headless provider set, or freeing provider caches after a long idle. The guest daemon uses the same full set, so this is also the guest's ceiling.

The budgets stay as written. Bench must go green by changing the code, not the number.

## Rules

- An optimization that breaks parity does not count.
- Re-run bench after every change that touches a hot path.
- A deliberate simplification with a known ceiling gets a `ponytail:` comment naming the ceiling and the upgrade path.
