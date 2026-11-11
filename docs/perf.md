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

### Mesa fork attempt (2026-11-03)

Superseded by a one-line Hyprland quirk. The guest compositor filtered ARGB out of its dmabuf feedback because the virtio-gpu primary plane is XR24-only. `quirks:skip_non_kms_dmabuf_formats = false` makes Hyprland advertise non-KMS formats too; the system Mesa then exposes 25 ARGB8888 configs with alpha 8, and the guest launcher shows the wallpaper behind it. No Mesa or Hyprland fork is needed. Proof: `vm/runs/demo/proof/launcher-alpha-hyprland-quirk.png`. The local Mesa fork was deleted.

### Guest parity (P1-P5)

- P1/P2: host DP-2 is 2560x1440, scale 1.6666666, 279.961Hz; guest Virtual-1 is 2560x1440, scale 1.6666666, 279.95999Hz.
- P3: host and guest both use `/home/gabriel/Documents/Wallpaper/wallhaven-0p2em3_2560x1440.png`; guest `awww query` reports the same image.
- P4: 676 host font families against 642 guest; the missing ones are CachyOS extras (Arabic/Syriac PCF), no guest-only families. The shell font `GoogleSansCode Nerd Font` resolves in both. Icon themes are the same 8; host has one extra `cachyos.svg` icon, not a theme. `breeze_cursors` is present in both.
- P5: fixed by the Hyprland non-KMS quirk; see the proof above.

### VM image build

`xmake vm bench [tag]` times `fetch`, `packages`, `golden` and appends one JSON line to `bench/images.jsonl` (gitignored). It uses `~/.cache/yudae-vm-bench`; `DOTFILES_VM_BENCH` moves the logs, `DOTFILES_VM_BENCH_CACHE` the cache.

| run | packages | golden | total |
| --- | --- | --- | --- |
| before | 4m29s | 49s | 5m18s |
| after | 3m41s | 49s | 4m32s |
| trimmed | 2m58s | 49s | 3m47s |
| folded | 2m44s | 0.09s | 2m44s |
| thin | 2m21s | 0.09s | 2m21s |
| fast | 54.8s | 0.09s | 54.8s |
| base | 53.9s | 0.09s | 53.9s |
| restore | 0.05s | 0.04s | 0.09s |
| final | 0.35s | 0.04s | 1.55s |

The thin cut also drops KDE and GNOME file managers and their dependency trees, Noto/CJK and extra fonts, printing and network daemons, and the desktop portals. It keeps the shell font, Meslo, DejaVu, emoji, Qt, Hyprland, audio, NetworkManager and the plugin toolchain. Result: 735MB download, 2.97G layer, 719 packages, shell screenshot and an in-guest `agent-cursor` build verified. `golden_setup` now runs `passwd -d root`; the guest reports `root NP`.

Cloud Hypervisor is not installed and is not a drop-in: it needs a direct kernel and initrd and has no dbus/GL path for the viewer. Installing it needs host root, which is unavailable by design.

The folded run makes the packages image bootable: the same provisioning boot writes the user units, fstab, enables them and sets the graphical target. `golden` is now an empty qcow2 overlay on packages, so it costs 0.09s instead of a second boot.

The trimmed run excludes firmware, QEMU, virtiofsd, VLC, tesseract, Firefox, qBittorrent, Prism Launcher, Rust, Zig, Clang, LLVM, CMake, Ninja, Docker, Podman, libvirt and the existing CachyOS/NVIDIA/Steam-only packages. It keeps gcc, make and pkg-config for plugin builds. The package layer drops from 6.5G to 4.2G and the guest has 946 packages instead of 1011; the shell, Hyprland and a scenario screenshot were verified on it. Its 1m20s fetch was a one-time cloud image download and is not in the total.

The second optimized run took 4m54s, so network variance is about 20s. Changes: one `pacman -Syu --needed` transaction instead of upgrade then install, `ParallelDownloads = 12`, `cache=unsafe`, `lazy_refcounts=on`, and `pacman -Scc` before poweroff. The 16G host package cache stays on 9p; virtiofs failed on the system QEMU with `vhost_set_vring_kick`.

`packages` and `golden` skip when their stamp still matches the host package list and user data (`packages.sha`, `golden.sha` in the cache); `--force` rebuilds. A cached `packages` is 0.3s, a cached `golden` is 0.01s. Both refuse to rebuild while any `vm/runs/*/disk.qcow2` exists, because that disk chain backs onto the layer being replaced; destroy those VMs first.

When the list changed, `packages` boots the existing layer and applies only the delta: installs the new explicit packages, removes packages dropped from the list, prunes orphans, clears the cache and runs `fstrim`. A qcow2 snapshot rolls back a failed or interrupted delta; the VM has a 20 minute watchdog. Above `DOTFILES_VM_PACKAGES_CAP_MB` (default 8192) the layer is rewritten with `qemu-img convert`. Measured on the isolated cache: full 2m44s, add one package 58s, remove it 57s, compaction 1m01s, golden 0.09s. `DOTFILES_VM_PACKAGES` points at a package list file instead of `pacman -Qqen`, for tests.

A host-side build was measured and rejected: pacman inside `unshare -r` installed 150 host packages (953MB) in 2m24s, slower than the guest, and unprivileged `/proc` and `/dev` mounts are denied. A from-scratch build under 60s is not reachable with pacman; the 58s delta is the practical floor, and the 2m44s figure is only for `--force` or a cold cache.

Direct kernel boot with a custom initramfs was also tried. The bash-init version reaches the installer in 0.1s and completes the transaction, but pacman's scriptlets and first-boot setup assume systemd is PID 1; the resulting guest fails D-Bus, logind and the user session. The systemd-target variant fixes that: the initramfs mounts the root, seed and 9p cache, installs `provision.target` and execs systemd, so scriptlets and first boot run normally.

With a warmed package cache and the multi-mirror prefetcher, a forced packages build is **54.8s** (54.1s on the previous run) with 13-19MB left to download. The prefetcher reads `urls.txt` from the previous build, takes the missing packages across four mirrors, and the guest copies new packages back into the cache. The kernel upgrade is ignored so the cloud kernel stays. A cold first build is 1m38s; the 54s figure is a rebuild with the cache present.

The parallel extraction variant was tried and rejected: `pacman -Syuw` plus `bsdtar` and `pacman -U --dbonly` produced a 64MB image without the package files, not a bootable build. It is disabled; the base is built with normal pacman.

The cloud image, package store and the built packages image persist in `~/.cache/dotfiles/vm-base`. A forced build with an empty `XDG_CACHE_HOME` restores the packages image by reflink in **0.047s** and creates the golden in **0.043s**, total **0.09s**. The restored image booted to D-Bus and the login prompt. The base itself is built in **53.9s** with normal pacman; a machine without the base pays that once.

The bench harness, with its own cache, reports `fetch 1.16s, packages 0.35s, golden 0.04s, total 1.55s` (`xmake vm bench final`). The fetch step is the base cloud checksum.

### Clock

QEMU uses `-rtc base=utc,clock=host`, so the guest RTC is the host wall clock. `vm/desktop` runs `hwclock -s` at Hyprland start, applies the host timezone from `vm/hoststate/timezone`, then disables NTP. `setGuestMode` disables NTP too. Guest `NTP=no`, `systemd-timesyncd` inactive/disabled; guest and host wall clocks stay within the vsock measurement margin.

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
