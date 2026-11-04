# VM work

The daemon is the control plane. Agents drive VMs through `yudae vm` and the MCP tools; they never talk to QEMU or the guest directly.

## Layers

```
Arch cloud image       pinned sha256, 20261101.620452
  packages layer       built from pacman -Qqen, host pacman cache over 9p, rebuilt only when missing
    golden layer       packages plus the guest daemon unit and autologin, booted once
      run overlay      one per VM, deleted on destroy
```

`xmake vm fetch` downloads the cloud image after probing mirrors. `xmake vm packages` builds the package layer (minutes, cached). `xmake vm golden` boots the packages layer once and snapshots the healthy state. `yudae vm create` only needs the golden layer. The cache lives in `~/.cache/dotfiles/vm`, run disks in `vm/runs/<name>`.

The dotfiles repo is mounted read-only over virtiofs at `/home/gabriel/dotfiles`. An uncommitted edit shows up in the guest at once. The guest runs the same `yudaemond` binary from that mount, with the same socket protocol and `yudae call`.

## GPU and display

virgl (`virtio-gpu-gl-pci`, OpenGL) is the default because the desktop is OpenGL. Venus (Vulkan) is not used. The guest renderer is `virgl (NVIDIA GeForce RTX 3070)`; check it with `QSG_INFO=1` in the guest. Every VM runs the patched QEMU from `~/qemu-linux/install/bin/qemu-system-x86_64` (fork `yumedots/qemu-linux`, branch `yudae`) with `-display dbus,p2p=yes,gl=on` and a second QMP socket, `vm/runs/<name>/display.qmp`. `YUDAE_QEMU` overrides the binary. `-nodefaults` plus `-vga none` keeps the PS/2 mouse from taking over.

The viewer is the Quickshell app, `shell/app-vms.qml`, built on `Yudae.Native.VmDisplay`. It reads `ScanoutDMABUF2` over the peer-to-peer D-Bus display, imports the dmabuf with EGL and draws it in the scene graph; `ScanoutMap` is the fallback. It sends absolute mouse, wheel and evdev->qnum keys over the D-Bus console. The `zwp_keyboard_shortcuts_inhibitor_v1` protocol sends host shortcuts to the guest while the window is focused; `SUPER+ALT+ESCAPE` is a `dont_inhibit` bind that leaves the VM. F11 is fullscreen and hides the sidebar. The app opens to gray last-viewed thumbnails; no VM renders until a card is clicked or opened with `--vm`. Thumbnails are captured on release into `vm/runs/<name>/thumb.jpg`.

The guest runs `shell/shell-guest.qml` (the autostart and `vm/shell` pick it with `systemd-detect-virt`). `vm/desktop-sync` copies the built `Yudae.Native` plugin into `vm/hostbin/yudae-native`; the guest's `vm/desktop` copies it to `~/.local/lib/yudae/qml` and restarts the shell. Guest overlay alpha is fixed with `quirks:skip_non_kms_dmabuf_formats = false`: Hyprland advertises non-KMS ARGB formats, system Mesa exposes ARGB8888, and the launcher shows the wallpaper. `yudae vm view <name>` sets the guest to 2560x1440 at scale 1.6667 and opens the app on that VM; the VM does not restart. Close the window or `yudae vm release <name>` to return to agent mode: 1536x864 at scale 1, kept live by the headless `yudae-pump` process the daemon starts at boot. QEMU uses `-rtc base=utc,clock=host` and the guest NTP is off.

A virgl VM cannot be saved or migrated, so GL VMs have no RAM-to-file save.

QMP `screendump` cannot read a virgl scanout, so GL screenshots run `grim` inside the guest and return the PNG over vsock. Non-GL VMs use QMP screendump.

## Sleep tiers

| tier | state | wake |
| --- | --- | --- |
| hot | running | none |
| warm | QMP `stop`, balloon inflated | milliseconds |
| parked | warm plus the cgroup's `memory.reclaim` | about a second |
| off | QEMU exited, overlay kept | boot from golden |

Each VM gets its own cgroup under `user@1000.service`, with `memory.max` and `cpu.max`. The daemon's own 512MB limit never sees guest RAM. The governor sleeps idle VMs after 5 minutes, parks them after 15 more, and stops them after an hour. Any tool call wakes the VM first; exec, state and screenshots retry the vsock connect for two seconds.

## Commands

Images are built through xmake, running VMs go through the daemon CLI:

```
xmake vm fetch | packages | golden | ensure | bench <name>
yudae vm create <name> [--cores N] [--mem MB] [--gl] [--from NAME]
yudae vm list | state | exec <name> <cmd> | screenshot <name> [path]
yudae vm key <name> <qcode...> | type <name> <text> | click <name> <x> <y> | move <name> <x> <y>
yudae vm wait <name> --until guest|<text>|exec:<cmd> [--timeout MS]
yudae vm sleep | park | wake | stop | destroy | snapshot <name> <tag> | restore <name> <tag> | fork <new> <from>
yudae vm view <name> | release <name> | scenario <name>
yudae open <name> [app] | vm gui <name> <app> | scroll <name> <dy> [x y]
yudae vm config <name> [--cores N] [--mem MB]
yudae app open vms --vm <name>
scripts/vm-test start | restart | shot [path] | run <cmd> | stop | destroy
```

Wallpaper and its daemon come from the host: `vm/desktop-sync` records the active path from `shell/cache/settings.lua` and copies the `awww` binaries into `vm/hostbin` (gitignored); the daemon starts a read-only virtiofs share of the wallpaper directory and the guest's `vm/desktop` mounts it, starts `awww-daemon` and sets the same image. Wallpaper changes apply on the next `vm view`.

`scripts/vm-test` is the UI loop: it keeps a VM named `ui` (override with `VM_TEST_NAME`), waits for the guest shell, restarts quickshell after a host edit and returns full-resolution PNG screenshots from the guest. `vm_test` runs on the host; `vm/shell restart|wait` runs inside the guest.

Snapshots are offline: `yudae vm stop` exits QEMU and keeps the overlay, then `vm snapshot`/`vm restore` work, then `vm start` boots it again.

The same verbs are MCP tools under the project's `yudae` server. `vm view` marks the human as controller and opens the Quickshell app; agent key/type/click/move then fails with `HumanControl` until the viewer closes or `vm release`. The viewer inhibits host shortcuts while it is focused, so `ALT+SPACE`, `SUPER+1..0`, `SUPER+RETURN`, `SUPER+W`, `SUPER+B`, `SUPER+TAB` and `SUPER+SPACE` reach the guest; `SUPER+ALT+ESCAPE` bypasses the inhibitor and leaves the window.

Every run writes `vm/runs/<name>/vm.json` with the git base, dirty flag and host package-list hash, plus the serial log and screenshots, so a failure can be replayed on the same state.

## Verify

- VM checks: `vm/scenarios/<name>.json` with `context`, `steps` and `proof`.
- Stop every test instance when done.
