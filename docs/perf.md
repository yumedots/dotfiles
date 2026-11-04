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

## VM viewer, measured 2026-11-03

Host: RTX 3070, 615.78.08, Hyprland 0.57.0, QEMU 11.1.3, guest 2560x1440 at scale 1.6667, 279.96Hz. CPU from `/proc/<pid>/stat` deltas, GPU from `nvidia-smi` at 500ms, RSS from `/proc/<pid>/status`. 60s per scenario.

### GTK baseline (C1)

| scenario | qemu CPU | GPU | qemu RSS |
| --- | --- | --- | --- |
| S0 idle desktop | 20.8% | 6.8% | 1.80GB |
| S1 launcher open/close every 500ms | 125.6% | 23.9% | 2.06GB |
| S2 continuous animation | 363.6% | 29.8% | 2.13GB |

### Measured configs

`refreshRate` 279.96 is the guest CRTC mode, not delivered frames. The deliverable metric is frames the viewer actually receives per second. CPU from `/proc`, GPU from `nvidia-smi`, 30-60s.

| config | guest | qemu CPU | other CPU | GPU | RSS | status |
| --- | --- | --- | --- | --- | --- | --- |
| C1 GTK S0 | 2560x1440 1.6667 | 20.8% | - | 6.8% | 1.80GB | measured |
| C1 GTK S1 | 2560x1440 1.6667 | 125.6% | - | 23.9% | 2.06GB | measured |
| C1 GTK S2 | 2560x1440 1.6667 | 363.6% | - | 29.8% | 2.13GB | measured |
| C5 pump S2 | 1536x864 1.0 | 194.4% | pump 13.4% | 38.7% | qemu 1.86GB, pump 19MB | measured |
| C2 viewer windowed | - | - | - | - | - | needs host run |
| C3 viewer fullscreen | - | - | - | - | - | needs host run |
| C4 ScanoutMap | - | - | - | - | - | needs the map fallback |
| C6 egl-headless | - | - | - | - | - | needs a fresh boot |

The C5 pump is the agent baseline: no human window, 1536x864 at scale 1, guest still presenting. It is cheaper than GTK S2 on CPU (208% total against 364%) but the GPU sample is higher (38.7% against 29.8%); the viewer C3 numbers are pending because the host session is locked and the nested test output is 1514x398, not 2560x1440.

The native viewer does receive 150 `UpdateDMABUF` frames/s on the animation, so the ack/toy-client throttle from the spikes is gone. A screenshot of the viewer shows the guest bar, the animation and the sidebar.

### Frame path now proven

1. The guest cycles dmabuf scanouts. QEMU exports them with `ScanoutDMABUF2`, fourcc ``A B G R 8 8 8 8``/``X B G R``, modifier `0x0300000000e08014`. The viewer imports with `EGL_LINUX_DMA_BUF_EXT` and draws a `QSGSimpleTextureNode`.
2. QEMU caches the export by texture id; repeat scanouts become `UpdateDMABUF`.
3. `/home/gabriel/dotfiles/daemon/zig-out/bin/yudae-pump` keeps an agent VM presenting with no viewer, at 1536x864 scale 1.
4. `yudae vm view` stops the pump, sets 2560x1440 scale 1.6667 in the guest and opens `shell/app-vms.qml`; `vm release` restores 1536x864 and restarts the pump. No VM restart.

### Open bench work

- C2/C3 at 2560x1440 on the real host output (needs the host session unlocked).
- C6 `egl-headless` on the same guest sizes for the agent comparison.
- Input latency p50/p95 needs the guest evdev capture script.
- Per-delivered-frame CPU/GPU, not just totals.

## Rules

- An optimization that breaks parity does not count.
- Re-run bench after every change that touches a hot path.
- A deliberate simplification with a known ceiling gets a `ponytail:` comment naming the ceiling and the upgrade path.
