# VM work

The daemon is the control plane. Agents drive VMs through `yudae vm` and the MCP tools; they never talk to QEMU or the guest directly.

## Layers

```
Arch cloud image       pinned sha256, 20261101.620452
  packages layer       built from pacman -Qqen, host pacman cache over 9p, rebuilt only when missing
    golden layer       packages plus the guest daemon unit and autologin, booted once
      run overlay      one per VM, deleted on destroy
```

`xmake vm fetch` downloads the cloud image after probing mirrors. `xmake vm packages` builds the package layer (minutes, cached). `xmake vm golden` boots the packages layer once and snapshots the healthy state. `xmake vm create` only needs the golden layer. The cache lives in `~/.cache/dotfiles/vm`, run disks in `vm/runs/<name>`.

The dotfiles repo is mounted read-only over virtiofs at `/home/gabriel/dotfiles`. An uncommitted edit shows up in the guest at once. The guest runs the same `yudaemond` binary from that mount, with the same socket protocol and `yudae call`.

## GPU

virgl (`virtio-gpu-gl-pci`, OpenGL) is the default because the desktop is OpenGL. Venus (Vulkan) is per VM only. Headless uses `-display egl-headless`. `-vga none` keeps the guest from picking the emulated VGA instead of virtio-gpu. A virgl VM cannot be saved or migrated, so GL VMs have no RAM-to-file save.

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

```
xmake vm fetch | packages | golden | ensure
xmake vm create <name> [--cores N] [--mem MB] [--gl] [--from NAME]
xmake vm list | state | exec <name> <cmd> | screenshot <name> [path]
xmake vm key <name> <qcode...> | type <name> <text> | click <name> <x> <y> | move <name> <x> <y>
xmake vm wait <name> --until guest|<text>|exec:<cmd> [--timeout MS]
xmake vm sleep | park | wake | stop | destroy | snapshot <name> <tag> | restore <name> <tag> | fork <new> <from>
xmake vm view <name> | run_scenario <name> | bench <name>
```

Snapshots are offline: `vm stop` exits QEMU and keeps the overlay, then `vm snapshot`/`vm restore` work, then `vm start` boots it again.

The same verbs are MCP tools. `vm view` marks the human as controller; agent key/type/click/move then fails with `HumanControl` until the viewer closes or ten idle minutes pass. The viewer is a 2 fps screenshot mirror with input forwarding, not the D-Bus dmabuf path yet.

Every run writes `vm/runs/<name>/vm.json` with the git base, dirty flag and host package-list hash, plus the serial log and screenshots, so a failure can be replayed on the same state.

## Verify

- Nested checks while editing: `agents/skills/hypr-test.md`.
- VM checks: `vm/scenarios/<name>.json` with `context`, `steps` and `proof`.
- Stop every test instance when done.
