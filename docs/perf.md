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
| C2 viewer windowed S0 | 2560x1440 1.6667 | 61.9% | viewer 14.1, hypr 10.8 | 14.2% | qemu 1.78GB, viewer 263MB | measured |
| C2 viewer windowed S1 | 2560x1440 1.6667 | 141.7% | viewer 25.4, hypr 16.1 | 29.1% | qemu 1.81GB, viewer 263MB | measured |
| C2 viewer windowed S2 | 2560x1440 1.6667 | 441.3% | viewer 44.5, hypr 21.3 | 30.5% | qemu 1.82GB, viewer 263MB | measured |
| C3 viewer fullscreen S0 | 2560x1440 1.6667 | 73.6% | viewer 16.9, hypr 7.4 | 11.9% | qemu 1.81GB, viewer 262MB | measured |
| C3 viewer fullscreen S1 | 2560x1440 1.6667 | 139.3% | viewer 26.1, hypr 11.9 | 9.4% | qemu 1.81GB, viewer 264MB | measured |
| C3 viewer fullscreen S2 | 2560x1440 1.6667 | 439.3% | viewer 44.2, hypr 18.6 | 37.8% | qemu 1.86GB, viewer 266MB | measured |
| C4 ScanoutMap/pixmap | 2560x1440 | - | - | - | works, not timed |
| C6 egl-headless S2 | 1536x864 1.0 | 201.7% | - | 29.1% | 1.92GB | measured |

The C5 pump is the agent baseline: no human window, 1536x864 at scale 1, guest still presenting. The C6 `egl-headless` baseline at the same size is slightly cheaper: 201.7% CPU and 29.1% GPU against 207.8% total CPU (194.4% qemu + 13.4% pump) and 38.7% GPU. The dbus display therefore costs about 3% more CPU and 9.6 GPU points for agents, and it is kept because viewing then needs no VM restart. The earlier frozen-guest C5 numbers were invalid and are gone.

C2/C3 do **not** pass the C1 GTK bar: qemu CPU is 61.9-441.3% windowed and 73.6-439.3% fullscreen against GTK 20.8-363.6%, and the viewer adds 14.1-44.5% CPU and ~262MB RSS. The viewer is a real Quickshell process, not a thin GTK child; the honest result is that the native path is heavier. GPU is 11.9-37.8% against GTK 6.8-29.8%. Fan-out and frame count were not re-instrumented in this run.

The C4 fallback is proven separately with a non-GL guest (`virtio-gpu-pci`, llvmpipe, `-display dbus,p2p=yes`): QEMU sends `ScanoutMap` with a 2560x1440 memfd, stride 10240; the viewer mmaps it, swizzles BGRA to RGBA and uploads the texture. The first full scanout is lost to the listener-registration race, so the viewer nudges `SetUIInfo` once after connecting to force a fresh scanout. The screenshot is `vm/runs/demo/proof/scanout-map.png`. Not timed yet; the pixmap path copies and swizzles the whole frame.

The native viewer does receive 150 `UpdateDMABUF` frames/s on the animation, so the ack/toy-client throttle from the spikes is gone. A screenshot of the viewer shows the guest bar, the animation and the sidebar.

### Frame path now proven

1. The guest cycles dmabuf scanouts. QEMU exports them with `ScanoutDMABUF2`, fourcc ``A B G R 8 8 8 8``/``X B G R``, modifier `0x0300000000e08014`. The viewer imports with `EGL_LINUX_DMA_BUF_EXT` and draws a `QSGSimpleTextureNode`.
2. QEMU caches the export by texture id; repeat scanouts become `UpdateDMABUF`.
3. `/home/gabriel/dotfiles/daemon/zig-out/bin/yudae-pump` keeps an agent VM presenting with no viewer, at 1536x864 scale 1.
4. `yudae vm view` stops the pump, sets 2560x1440 scale 1.6667 in the guest and opens `shell/app-vms.qml`; `vm release` restores 1536x864 and restarts the pump. No VM restart.
5. The native plugin is copied into `~/.local/lib/yudae/qml` by `vm/desktop`, `shell/shell-guest.qml` imports it, and its `registerTypes` calls `QQuickWindow::setDefaultAlphaBuffer(true)`. The guest overlay alpha is fixed: `quirks:skip_non_kms_dmabuf_formats = false` makes Hyprland advertise non-KMS ARGB formats, system Mesa exposes 25 ARGB8888 configs and the launcher shows the wallpaper. Proof: `vm/runs/demo/proof/launcher-alpha-hyprland-quirk.png`.

### Venus + zink attempt (2026-11-03)

Venus was tried as the virgl alpha fix. QEMU ran with `virtio-gpu-gl-pci,blob=on,hostmem=2G,venus=on`; the guest installed `vulkan-virtio`. `vulkaninfo` sees `Virtio-GPU Venus (NVIDIA GeForce RTX 3070)` and `VK_KHR_wayland_surface`, but windowed use is broken on this host: `vkcube` selects the Wayland WSI and dumps core, and zink fails with `ZINK: failed to choose pdev` on every window surface, falling back to llvmpipe. `eglinfo -p wayland` sees zink only through the EGL device path, not a window. QEMU was reverted to plain `virtio-gpu-gl-pci`. Proof: `vm/runs/demo/proof/venus-vkcube.log`, `venus-gl-zink.txt`, `venus-gl-virgl.txt`.

The virgl GL benchmark (`vm/bench/eglbench.c`, Wayland EGL, 1920x1080 FBO): heavy 240 frames 473-592 fps, draws 120 x 4096 47-51 fps (193k-208k draws/s). Host QEMU 20.9% CPU and 1.94GB RSS over 10s. A zink number is not comparable because windowed zink fell back to llvmpipe.

### Mesa fork attempt (2026-11-03)

Superseded by a one-line Hyprland quirk. The guest compositor filtered ARGB out of its dmabuf feedback because the virtio-gpu primary plane is XR24-only. `quirks:skip_non_kms_dmabuf_formats = false` makes Hyprland advertise non-KMS formats too; the system Mesa then exposes 25 ARGB8888 configs with alpha 8, and the guest launcher shows the wallpaper behind it. No Mesa or Hyprland fork is needed. Proof: `vm/runs/demo/proof/launcher-alpha-hyprland-quirk.png`. The local Mesa fork was deleted.

### Guest parity (P1-P5)

- P1/P2: host DP-2 is 2560x1440, scale 1.6666666, 279.961Hz; guest Virtual-1 is 2560x1440, scale 1.6666666, 279.95999Hz.
- P3: host and guest both use `/home/gabriel/Documents/Wallpaper/wallhaven-0p2em3_2560x1440.png`; guest `awww query` reports the same image.
- P4: 676 host font families against 642 guest; the missing ones are CachyOS extras (Arabic/Syriac PCF), no guest-only families. The shell font `GoogleSansCode Nerd Font` resolves in both. Icon themes are the same 8; host has one extra `cachyos.svg` icon, not a theme. `breeze_cursors` is present in both.
- P5: fixed by the Hyprland non-KMS quirk; see the proof above.

### vm/compare

`vm/compare` captures host and viewer-fullscreen at 2560x1440 for 8 scenes, masks the dynamic bar regions (workspaces, clock, stats) and reports ImageMagick RMSE. Side-by-side PNGs are in `vm/runs/demo/compare/`.

| scene | dimensions | masked RMSE |
| --- | --- | --- |
| idle | 2560x1440 | 1043.74 |
| bar | 2560x1440 | 4852.83 |
| launcher | 2560x1440 | 5152.76 |
| launcher-fire | 2560x1440 | 7992.21 |
| calendar | 2560x1440 | 5205.03 |
| power | 2560x1440 | 1446.53 |
| tiled | 2560x1440 | 6711.25 |
| fullscreen | 2560x1440 | 3804.78 |

Expected differences: `launcher-fire` shows host-only games in the guest query; calendar meters and the guest cursor differ; the tiled/fullscreen terminals are at different window positions. The images were inspected; these are not pixel-identical.

### Input latency

Key input measured with a guest evdev marker written to `/dev/ttyS0` and timestamped on the host: 20 samples, p50 **5.49ms**, p95 **16.00ms** (min 4.59, max 16.00). The marker path is viewer key -> guest evdev -> serial; it does not use guest wall-clock compared with host. Mouse latency was not captured because the virtio-tablet marker produced no samples in this run; mouse position mapping is proven separately.

### Clock

QEMU now uses `-rtc base=utc,clock=host`; guest `timedatectl set-ntp false` is applied by `setGuestMode` and `vm/desktop`. Guest `NTP=no`, `systemd-timesyncd` inactive/disabled; guest and host wall clocks stay within the vsock measurement margin.

### Full daemon budget

The headless daemon still passes 3.6MB idle RSS and 9.1s cold build against 8MB/20s. The full desktop daemon measures ~41.6MB/80s because it carries the launcher index, icon cache and every UI provider. Proposal: keep 8MB/20s as the control-plane gate and make the full desktop budget informational (48MB/90s), or lazy-load the launcher index/icons behind first use. That change is not made in this round; the measured numbers are the finding.

### Open bench work

- C2/C3 are measured above; they miss the C1 GTK bar.
- C6 `egl-headless` on the same guest sizes for the agent comparison.
- Mouse input latency still needs a tablet marker capture.
- Per-delivered-frame CPU/GPU, not just totals.

## Rules

- An optimization that breaks parity does not count.
- Re-run bench after every change that touches a hot path.
- A deliberate simplification with a known ceiling gets a `ponytail:` comment naming the ceiling and the upgrade path.
