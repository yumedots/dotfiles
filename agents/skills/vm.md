# VM work

The daemon is the control plane. Agents drive VMs through `yudae vm` and the MCP tools; they never talk to QEMU or the guest directly.

## Layers

```
Arch cloud image (pinned sha256)
  packages layer   built from the host package list, rebuilt only when the list hash changes
    golden layer   desktop booted healthy, guest yudaemond up
      run overlay  one per VM, deleted on destroy
```

The host pacman cache and the AUR helper's built packages are mounted read-only over virtiofs, so building the layer downloads almost nothing. The dotfiles repo is mounted read-only; an uncommitted edit shows up at once.

## GPU

virgl (`virtio-gpu-gl`, OpenGL) is the default because the desktop is OpenGL. Venus (Vulkan) is per VM only. Headless uses `-display egl-headless`; a human uses `-display dbus,gl=on`. A virgl VM cannot be saved or migrated, so GL VMs have no RAM-to-file save.

## Sleep tiers

| tier | state | wake |
| --- | --- | --- |
| hot | running | none |
| warm | QMP `stop`, balloon inflated | milliseconds |
| parked | warm plus the VM cgroup's memory reclaimed to swap | about a second |
| off | QEMU exited, overlay kept | boot from golden |

Any tool call wakes the VM before it runs; the agent never sees sleep.

## Commands

```
xmake vm create [name] [--cores N] [--mem MB] [--gl]
xmake vm list | sleep | wake | destroy | view | screenshot
xmake vm exec <name> <cmd...>
xmake vm scenario <name>
```

The same verbs are MCP tools. Every run writes `runs/<id>/` with the base hash, package-list hash, dotfiles ref and dirty diff, scenario, logs and screenshots, so a failure can be replayed on the same state.

## Verify

- Nested checks while editing: `agents/skills/hypr-test.md`.
- VM checks: `vm/scenarios/<name>.json` with `context`, `steps` and `proof`.
- Stop every test instance when done.
