# TODO: Quickshell-native VM viewer app + window primitive

Repo: `~/dotfiles`, branch `yudaemond`. Read `AGENTS.md`, `plans.md`, `agents/skills/{quickshell,daemon,vm}.md` first.

## Goal (from the user, verbatim intent)

One real app window (xdg_toplevel, movable/tiled/floating in Hyprland) built with Quickshell QML:
- Left: a sidebar listing the VMs (from yudaemond), showing which agent works on each one: harness (opencode / claude / codex), session (id + title) and how many minutes it has been working.
- Right: the live VM display. It must be a 1:1 copy of the host desktop: same resolution, same fractional scale, same refresh rate, same wallpaper and awww daemon, same everything. Fractional scaling must work.
- The app window is built on a reusable **window primitive**, because the user will build more apps on it later.
- Everything must be proven with screenshots and comparisons against the real desktop, plus benchmarks (CPU and GPU for QEMU, the viewer and Hyprland) against the current QEMU GTK window. If the GTK window turns out faster, say so with numbers.
- Agent (non-human) mode must cost less: render fewer pixels when nobody is viewing.
- Clock fix applied: `-rtc base=utc,clock=host` + guest NTP off.

## Rules (from AGENTS.md, enforced)

- No code comments. Short TLDR replies. Lazy-senior ladder: reuse, delete, smallest diff.
- No installs without asking in the 3-option format (root now / another way / user does it). Everything below needs nothing new: Qt6 headers, EGL dmabuf import with modifiers, wayland-protocols 1.50, qemu-ui-dbus, xmake qt rules (moc, qmltyperegistrar), Quickshell 0.3.2 `//@ pragma Env|AppId` are all installed. `pidstat` is NOT installed; read `/proc/<pid>/stat` instead.
- Git: commit only in small one-line lowercase-past-tense blocks, and only when the user allows. Confirm first.
- The user allowed driving their real mouse and keyboard. Start `ydotoold --socket-path=$XDG_RUNTIME_DIR/.ydotool_socket --socket-perm=0600` with setsid and kill it after. Absolute moves: `hyprctl dispatch 'hl.dsp.cursor.move({x=X,y=Y})'`. Keys: `ydotool key 56:1 57:1 57:0 56:0` (Alt+Space). Leave the user's desktop as you found it.
- Hyprland is configured in Lua: `hl.dsp.focus({workspace=N})`, `hl.dsp.window.fullscreen()`, `hl.dsp.focus({window=w})` where w comes from `hl.get_windows()` inside `hyprctl dispatch 'function() ... end'`. `hyprctl keyword` does not work.

## Current state (all committed)

- VMs: KVM (`-machine q35,accel=kvm -nodefaults`), virgl GPU. The guest renderer is `virgl (NVIDIA GeForce RTX 3070)`, GL 4.2.
- Viewed VMs: `-display gtk,gl=on,grab-on-hover=off,full-screen=on` (`daemon/src/providers/vms/qemu.zig`). Headless VMs: `egl-headless` at 1280x720 (`vm create --headless`). `vm view` restarts a headless VM to give it a window.
- `vm view` focuses the window and fullscreens it via a Lua dispatch (`focusVmWindow` in `daemon/src/cli.zig`).
- `hypr/binds.lua` has a forwarding hack (`activeVm`/`vmAction`/`vmKeys`) that sends Alt+Space, Super+N and others into the focused QEMU window, plus `SUPER+ALT+ESCAPE` to leave it. Delete the hack once the new viewer inhibits shortcuts properly.
- Guest desktop sync: `vm/desktop-sync` (host) copies the awww binaries, the wallpaper and the timezone into `vm/hostbin`, `vm/hostwall` and `vm/hoststate` (all gitignored). `vm/desktop` (guest) applies them. `bootVm`/`viewVm` call them.
- The guest daemon finds Hyprland by scanning `$XDG_RUNTIME_DIR/hypr` (`daemon/src/primitives/hypr.zig findSignature`). The guest bar workspaces work.
- UI test loop: `scripts/vm-test start|restart|shot|run|stop`. `vm/shell restart|wait` runs inside the guest.
- Launcher has a "Virtual machines" mode (list / open / kill). `shell/features/launcher/Launcher.qml` shows its first screen on open (`syncLive`).
- VM `demo` exists (stopped or running). Its run dir is `vm/runs/demo`. Golden image is at `~/.cache/dotfiles/vm/golden.qcow2`.

## Known problems this work must solve or report

1. Resolution: the GTK window is 1536x864 logical, so the guest renders 1536x864 and Hyprland upscales it to 2560x1440. It is blurrier than native apps.
2. The guest cursor is drawn by the host on top of the guest. Users see the host arrow.
3. No real keyboard capture (Wayland). This is why the binds hack exists.
4. Guest overlays (launcher, calendar) have an opaque black backdrop. The guest Qt reports `alphaBufferSize 0` under virgl. This is inside the guest framebuffer, so a new viewer will NOT fix it by itself. Investigate the guest EGL configs (`eglinfo` in the guest, `QSG_INFO=1`). It was also reported once on the host with the calendar open. Re-verify on the host with no QEMU window on that workspace before blaming the guest.
5. Guest monitor: `Virtual-1` falls back to scale 1 because `shell/cache/display.lua` only knows DP-1 and DP-2. The guest must get the host primary output's mode and scale (2560x1440@279.96, 1.6667).

## Decisions locked by the user

1. C++ for the one QML display item (`Yudae.Native`), Zig for everything daemon-side.
2. Delete the GTK viewer path and the `hypr/binds.lua` forwarding hack once the new viewer is proven.
3. Agent mode = same logical layout at scale 1 (guest 1536x864) when no viewer is attached.
4. Commit in small one-line blocks as each step is proven.

## Architecture

```
QEMU  -display dbus,p2p=yes,gl=on   (all VMs, human or agent)
  |  2nd QMP socket per VM: vm/runs/<name>/display.qmp
  |  viewer: socketpair -> QMP getfd (SCM_RIGHTS) -> add_client protocol=@dbus-display fdname=...
  v
sd-bus peer connection (C API, the same lib the daemon already links for tray/notify)
  Console.RegisterListener(fd)  -> QEMU calls our Listener:
     ScanoutDMABUF2 / UpdateDMABUF  -> EGLImage (EGL_LINUX_DMA_BUF_EXT + modifiers) -> GL texture -> QSGTexture
     ScanoutMap / Update            -> memfd fallback, glTexSubImage on damage
     CursorDefine / MouseSet        -> set as the window's QCursor (guest cursor shape, host-drawn, zero lag)
  Console.SetUIInfo(w,h in device px) -> guest resolution follows the viewport (dynamic resize)
  Keyboard.Press/Release(qnum), Mouse.SetAbsPosition / Press / Release / wheel
```

- Why C++ and not Zig for the viewer: a QML render item must be a C++ `QQuickItem`, which needs moc. The repo already writes its sd-bus code in C (`daemon/src/c/*.c`).
- Build: an xmake target with `add_rules("qt.qmlplugin")`, output to `shell/native/qml/Yudae/Native`. Add it to `xmake build`. Wayland protocols (keyboard-shortcuts-inhibit, pointer-constraints) are generated with wayland-scanner from `/usr/share/wayland-protocols`. The wl_surface comes from `QNativeInterface::QWaylandWindow`.
- Ack `UpdateDMABUF` only after the frame is swapped (`QQuickWindow::frameSwapped`). This paces QEMU to what is actually presented.
- Shortcut capture: when the viewer is focused and the pointer is inside it, create `zwp_keyboard_shortcuts_inhibitor_v1`, so Alt+Space and Super+N go to the guest natively. Escape chord: keep `SUPER+ALT+ESCAPE` as a host bind with the Hyprland inhibitor-bypass flag. Find the Lua option name (Hyprland 0.57); the viewer also drops the inhibitor on it. Then delete the binds.lua forwarding hack.
- Keycodes: Wayland `nativeScanCode()` is evdev+8. QEMU wants qnum, which needs an evdev->qnum table. Ship a tiny generated table plus ONE runnable check (assert a few known keys).
- Agent mode: no listener attached. `SetUIInfo` gives the same logical layout at scale 1, i.e. guest 1536x864 at scale 1 (0.36x the pixels of 2560x1440). Agent click coordinates stay in the same logical space. When a viewer attaches, `SetUIInfo` makes it 2560x1440 and the guest scale 1.6667, with no VM restart. This deletes the `view` flag, the restart-on-view code and the GTK/egl-headless branches. Only do this if spike (d) proves dbus-without-listener costs no more than egl-headless.

## Window primitive

- `shell/ui/AppWindow.qml`: wraps Quickshell `FloatingWindow` with title, app id (via `//@ pragma AppId` in the entry), min size, shell styling (`Config` surface/fonts, `HyprBorder`), close quits the process, and fullscreen toggle (F11).
- Entry: `shell/app.qml` loads `features/<name>/App.qml` from env `YUDAE_APP`. The config root stays `shell/`, so `qs.ui` and `qs.services` resolve. If the AppId pragma cannot be per-app with one entry file, use one tiny entry per app in `shell/` (`app-vms.qml`); decide in spike (a).
- Launch: `yudae app open <name>` (cli.zig) spawns `quickshell -p shell/app.qml` with the env, single instance (raise if running). The launcher's VM mode and `vm view` open the `vms` app selected on that VM.
- Each app is its own quickshell process, so a crash or reload never touches the bar.

## VM app UI (`shell/features/vms/App.qml`)

- Right: `VmDisplay` (native item) for the selected VM. Windowed: the guest resolution follows the viewport (`SetUIInfo` with device pixels, guest scale = host scale). Fullscreen (F11): the sidebar hides and the guest is exactly the host output: 2560x1440, 1.6667.
- Left sidebar rows from the `vms` snapshot: name, tier, controller, harness, session title, minutes working, cpu/rss. Actions: take control (view), release, stop, destroy. No on-screen hints or shortcut text (AGENTS.md rule).
- Daemon fields to add (Zig, `daemon/src/providers/vms.zig` + `daemon/src/mcp.zig`):
  - `harness`: MCP `initialize` clientInfo.name (opencode / claude-code / codex).
  - `session`: env of the MCP process (`OPENCODE_SESSION_ID` exists; find the Claude Code / Codex equivalents by checking the env of their MCP child).
  - `agentSinceMs`, `lastCallMs`: stamped on every vm_* call from that session.
  - Session title: joined in the daemon from the existing opencode/claude/codex providers (QML stays dumb). Add one zig test for the JSON fields.

## Guest parity (each item proven by comparison)

- P1 monitor: a rule for `Virtual-1` in `hypr/monitors.lua` = the host primary output's mode + scale (recorded by `vm/desktop-sync` into `vm/hoststate`; the rule is harmless on the host). Proof: `hyprctl monitors -j` width/height/scale/refreshRate equal on host and guest.
- P2 refresh: check whether `SetUIInfo` / virtio-gpu EDID carries refresh. If the guest falls to 60/75Hz, report it; a custom mode in the Hyprland rule may work.
- P3 wallpaper + awww: done; keep it.
- P4 fonts, icon theme, cursor theme (hyprcursor/XCURSOR) present in the guest. Diff `fc-list` and theme dirs host vs guest.
- P5 overlay alpha (problem 4).
- Expected differences, list them but don't chase: the agent face, tray, media and opencode state.
- Compare tool `vm/compare`: host `grim` of a scene vs `grim` of the viewer window fullscreen ON THE HOST (what the user sees), both 2560x1440. Mask dynamic regions (clock, stats). Metric: ImageMagick `compare -metric RMSE` on the masked area plus exact-dimension check. Scenes: idle desktop, bar, launcher open, launcher "fire", calendar open, power menu, a tiled alacritty, a fullscreen app. Save side-by-side PNGs in `vm/runs/<name>/compare/`. Read every image yourself.

## Benchmarks (`vm/bench-view`, JSON per run, table in docs/perf.md)

- Configs: C1 GTK window (record BEFORE removing it), C2 viewer windowed, C3 viewer fullscreen, C4 viewer ScanoutMap fallback, C5 dbus with no listener (agent), C6 egl-headless (agent baseline).
- Scenarios, 60 s each: S0 idle desktop; S1 launcher open/close every 500 ms (guest `vm ui`); S2 continuous guest animation (alacritty scrolling or a QML animation).
- Metrics:
  - CPU% from `/proc/<pid>/stat` deltas for qemu, the viewer, host Hyprland and virtiofsd.
  - GPU from `nvidia-smi --query-gpu=utilization.gpu,memory.used -lms 500` and `nvidia-smi pmon -s um`.
  - Frames/s: viewer UpdateDMABUF count and guest frame count.
  - Input latency: viewer key/mouse timestamp -> guest evdev timestamp (the `cap.py` capture technique from the session, push it with `vms push`) -> next update, median and p95.
  - RSS.
- Pass bar: viewer ≤ GTK on CPU and GPU in every scenario, fps parity with the guest, latency p95 within one host frame of GTK. Report honestly if not.

## Risks and fixes (run these spikes before building anything else)

1. Zero-copy buffer shows black on NVIDIA (SPICE GL did).
   - Likely cause: a format/modifier mismatch on import. Fix: use `ScanoutDMABUF2`, which carries the fourcc + modifier per plane, and import with `EGL_EXT_image_dma_buf_import_modifiers` (present on this driver). Check `eglQueryDmaBufModifiersEXT` for the fourcc first.
   - If import still fails, use QEMU's `ScanoutMap` (memfd shared memory) and upload only damaged rects with `glTexSubImage2D`. Measure the extra CPU. ~2560x1440x4 = 14 MB per full frame; damage-only keeps it small on an idle desktop.
   - Last resort: keep the viewer UI and fall back to the GTK window for display. Report numbers to the user before choosing this.
2. Guest refresh rate drops to 60/75 Hz (no GTK window to report the monitor rate).
   - Check what `SetUIInfo` and the virtio-gpu EDID tell the guest (`hyprctl monitors -j` availableModes).
   - Fix A: a guest Hyprland rule for `Virtual-1` with mode `2560x1440@279.96` (virtio-gpu often accepts custom modes).
   - Fix B: virtio-gpu has no real vblank, so the guest renders on damage. Pacing comes from the viewer acking `UpdateDMABUF` after each swap, so the effective rate is the host's. Measure guest fps during the S2 animation; if it reaches host rate, the reported number does not matter.
3. Black backdrop behind guest overlays (launcher, calendar). This is inside the guest; the viewer does not fix it.
   - Cause: the guest Qt surface has no alpha (`alphaBufferSize 0` under virgl), so transparent layer surfaces render opaque black.
   - Check `eglinfo` in the guest for EGL configs with alpha on virgl, and `QSG_INFO=1` for the chosen format.
   - Fix A: request an alpha buffer in the guest Qt (default `QSurfaceFormat` with `setAlphaBufferSize(8)`), via a Quickshell option or a tiny guest-only module in `Yudae.Native`.
   - Fix B: if virgl exposes no alpha config, fix in Mesa/virgl config (`MESA_` env) or report it as a virgl limit.
   - First re-check the host: with no QEMU window on the workspace, open the calendar. It must be transparent on the host. If it is not, that is a shell bug in `shell/ui/Tooltip.qml`, not the VM.
4. Quickshell may not load an external compiled QML module, or `AppId` may be per-process only.
   - Fix: `//@ pragma Env QML_IMPORT_PATH=...` in the entry; if the pragma is ignored, set the env in `yudae app open`. One entry file per app if `AppId` cannot be set from env.
5. Hyprland may not let a bind bypass the shortcuts inhibitor.
   - Fix: the viewer handles the escape chord itself and drops the inhibitor; also drop it on focus loss.
6. dbus display with no listener might cost more than egl-headless for agents.
   - Fix: keep egl-headless for agent VMs and restart into dbus on first view. Costs one restart; measure both.

## Order of work (stop and report at each spike result)

0. Spikes, each with a throwaway test and proof:
   a. Quickshell loads the compiled `Yudae.Native` module (via `//@ pragma Env QML_IMPORT_PATH=...`). `FloatingWindow` + AppId gives a movable xdg_toplevel with the right class (`hyprctl clients`).
   b. p2p dbus via the second QMP socket. `ScanoutDMABUF2` imports and displays a non-black frame on NVIDIA. HIGH RISK: SPICE GL dmabuf was black on this GPU. If it fails, try `ScanoutMap` and measure.
   c. `SetUIInfo` changes the guest resolution live; check the refresh rate.
   d. CPU/GPU of dbus-no-listener vs egl-headless.
   e. Shortcuts inhibitor works in Hyprland, plus the bind-bypass flag for the escape chord.
   Also record the C1 baseline now.
1. Window primitive + `yudae app open` + launcher hook. Proof: move, float, tile, close; bar unaffected.
2. `VmDisplay` item: dmabuf, damage, ack, fallback, cursor, absolute mouse, wheel, keyboard qnum + check, inhibitor, dynamic resize.
3. Daemon: dbus display for all VMs, second QMP socket, no restart on view, agent-mode SetUIInfo, harness/session fields + test. Delete the GTK path, the `view` flag and the binds hack.
4. App UI (display + sidebar + actions).
5. Guest parity P1–P5 + `vm/compare` scenes.
6. Benchmarks + docs (`docs/perf.md`, `agents/skills/vm.md`, `docs/agent-tooling.md`, `docs/architecture.md` repo map with `shell/native`). `xmake lint`, `xmake test`, `cd daemon && zig build test` green.
7. Then the clock fix, with the user's go.
8. Last: close what is still open in `plans.md`.
   - The full desktop `yudaemond` fails the idle-RSS (8 MB, measured ~42 MB) and cold-build (20 s, measured ~80 s LLVM) gates; only `yudaemond-headless` passes. Find what holds the RSS (launcher index, icons, weather, GitHub, media caches) with `xmake bench`, cut or lazy-load it, and report the numbers. If the gates cannot be met for the full daemon, say so and propose a budget change instead of hiding it.
   - Update `plans.md` sections 3 (Human view, `vm view`) to what was built: the Quickshell VM app on the dbus dmabuf path.

## Next before compare/bench (user, 2026-11-03)

1. Launcher: done. The entry opens the vms app; the launcher has no VmSection reference. VmSection.qml remains only for ProcessPanel's VM usage.
2. vms app landing: done. Gray last-viewed thumbnails; no live render until a card click. Proof: `vm/runs/demo/proof/gallery.png`, `gallery-live.png`.
3. Mouse: mapping to the letterboxed rect and 125 Hz coalescing done; key latency p50 5.49ms/p95 16.00ms. Mouse latency was not captured because the tablet marker produced no samples; visual mapping is proven.
4. Aspect: fixed. The guest stays at 2560x1440 scale 1.6667 and the preview letterboxes. The app no longer auto-renders the first VM at 1536; a click/`--vm` sends view first, so F11 is 1:1.
5. Virgl alpha: fixed. Hyprland was filtering ARGB because the guest primary plane is XR24-only; `quirks:skip_non_kms_dmabuf_formats = false` advertises non-KMS formats, system Mesa exposes ARGB8888, and the guest launcher is transparent. Proof: `vm/runs/demo/proof/launcher-alpha-hyprland-quirk.png`. No Mesa/Hyprland fork needed; the local Mesa fork was deleted.
6. Wallpaper: stop copying the wallpaper into `vm/hostwall`. Read the active path from `shell/cache/settings.lua` in the guest and mount that directory read-only over virtiofs so the guest uses the same file. Keep the awww binary copy only if the guest lacks it.
7. `vm/compare` done: 8 scenes, exact 2560x1440, masked RMSE in `docs/perf.md`; C2/C3 measured; key latency recorded. Mouse latency still open.

## Clock

- QEMU uses `-rtc base=utc,clock=host`; guest NTP is off (`timedatectl set-ntp false` in setGuestMode and vm/desktop). Guest NTP=no, timesyncd inactive.

## Gotchas learned this session

- `scripts/yubuild` takes ~80 s, then `systemctl --user restart yudaemond`. Fast compile check: `cd daemon && zig build -Drelease=true -Dllvm=false --cache-dir /tmp/zig-check --prefix /tmp/yudae-check`.
- A stale `qmp.sock` made boots fail; the daemon now deletes it before spawn.
- `yudae vm exec` quoting is painful: write a script locally, `yudae call vms push '{"name":..,"path":..,"to":..}'`, then exec it.
- Guest env for Hyprland tools: `XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr|head -1) WAYLAND_DISPLAY=wayland-1`.
- Agent input fails with `HumanControl` after `vm view`. Pass `"human":true` or `vm release`.
- The host quickshell live-reloads on save. A bad QML edit shows "Config reload failed" on the user's screen. Lint first: `/usr/lib/qt6/bin/qmllint -I /tmp/qmlimport <file>`. Making the launcher window card-sized broke the host launcher once; it was reverted.
- `grim` can hang: wrap it in `timeout 10`. Quickshell logs: `/run/user/1000/quickshell/by-id/<id>/log.log`.
- Earlier failed paths (don't retry): spicy + SPICE gl=on (black on NVIDIA), SPICE + egl-headless (relative mouse, pinned cursor), SDL display, GTK with `GDK_BACKEND=x11` (EGL assert), GTK `grab-on-hover=on` (trapped the user; Ctrl+Alt+G release unreliable).
