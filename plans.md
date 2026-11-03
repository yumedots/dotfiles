# Plans

TLDR: one repo, split by what a thing is. xmake is the single entry point. `vm` runs disposable KVM machines (from `~/playground`) for real-session tests. One IPC door for commands.

## 1. Repo layout

Today `~/.config` is the repo, so app configs, quickshell, hyprland, the daemon and scripts all sit together. Target: the repo lives outside `~/.config`, and only plain app configs are symlinked into it.

```
dotfiles/
  config/            plain app configs, one dir per app (alacritty foot ghostty btop gtk-3.0 gtk-4.0 zsh yazi micro lazygit opencode ...)
                     each dir is symlinked to ~/.config/<name>
  hypr/              hyprland conf + cursor plugin (C++); the one non-config symlinked, hyprland reads ~/.config/hypr
  shell/             quickshell, run with `quickshell -p`, never symlinked
    features/<name>/ one folder per feature: Card.qml Widget.qml Service.qml feature.json
    ui/              primitives used twice or more
    lib/ greeter/ lock/ launcher/
  daemon/            yudaemond (Zig); src/providers/<name>.zig pairs with features/<name>
  systemd/ scripts/
  vm/                see section 3
  docs/              reference: how the system is shaped
  agents/skills/     task guides: how to do X
  xmake.lua + one xmake.lua per dir
  plans.md AGENTS.md README.md
```

Rules:
- A feature has one name. `features/weather/` on the QML side, `providers/weather.zig` on the daemon side. Add or delete both together.
- `config/` has no code. Anything with logic leaves it.
- `AGENTS.md` becomes an index. Procedure goes in `agents/skills/`, reference in `docs/`.
- Only `xmake link` writes into `~/.config`. It refuses to overwrite a real file and prints what it would replace.

Moves, in order (each one verified with hypr-test before the next):
1. Inside the current repo: create `config/`, `shell/`, `daemon/`, `hypr/` and move things in. Fix every path (systemd units, greetd, hypr exec lines, `scripts/yubuild`, `hypr-test`).
2. Add `xmake link`, replace the files in `~/.config` with symlinks.
3. Move the repo root to `~/dotfiles` (the existing clone there is a stale copy of the same remote, replace it).

Risk: the shell and greeter currently assume `~/.config/quickshell`. Both must run from the repo path. AGENTS.md rule "everything the shell runs lives in ~/.config/quickshell" changes to "lives in the repo, run with `-p`".

## 2. xmake as the single entry point

`xmake <task>` replaces remembering scripts. xmake orchestrates, it does not replace the real builders.

| task | does |
| --- | --- |
| `xmake build` | daemon (wraps `zig build`), cursor plugin (native C++ target) |
| `xmake link` | symlink `config/*` and `hypr/` into `~/.config` |
| `xmake lint` | qmllint on `shell/`, `node shell/lib/check.js` |
| `xmake test` | daemon parsers/protocol tests, qml fixtures, idle-spawn test |
| `xmake bench` | `yudaemond bench`, compared with `bench/baseline.json` |
| `xmake hypr` | nested hypr-test (start, shot, run, stop) |
| `xmake vm ...` | section 3 |
| `xmake doctor` | what is missing and why |

Keep `zig build` underneath: the build budgets (incremental <2s, cold <20s, binary <3MB) are measured on it, and `scripts/yubuild` prints them. xmake calls it and reports the same numbers. Do not reimplement Zig compilation in Lua.

## 3. VM work for agents and humans

The daemon is the control plane. Nothing lives in a separate broker.

### Where it lives

- **Code:** `daemon/src/providers/vms/` in Zig, inside yudaemond. Split by job: `qmp.zig`, `vsock.zig`, `budget.zig`, `tiers.zig`, `cgroup.zig`, `images.zig`. QMP is JSON over a unix socket and vsock is a socket family, so std is enough. No C library is needed. If one ever is (libvirt is not), it needs your explicit yes first.
- **Why Zig and not Go:** the daemon already owns state, the socket protocol, the MCP and the bench budgets. A Go daemon would be a second runtime, a second protocol and an extra hop, for libraries we do not need.
- **Images and tasks:** `vm/` with xmake, taken from playground: the overlay and snapshot tasks, the pinned fetch with mirror speed-test, `bench.sh`, the qemu command builder. Dropped: the Mac pieces (GPUI window, cocoa, hvf, the QEMU fork, `tryDisplay`, the Go `firstBoot`, which cloud-init and the packages layer replace). Playground stays an archive. Its old uncommitted work is in `git stash` there.
- **Merge:** copy what is useful into `vm/`. No submodule.

### Control plane

```
host yudaemond  ──QMP unix socket──▶  qemu (one per VM): screendump, input, stop/cont, save/restore, balloon, block
      │
      └──vsock (CID per VM)────────▶  guest yudaemond (same binary, headless providers): state, doctor, ui tree, call, exec
```

- The host daemon runs every VM and owns all screenshots. Agents never talk to QEMU or the guest directly.
- The guest runs the same yudaemond, so the same snapshot JSON, the same `yudae call` and the same `ui tree` work inside and outside a VM. vsock needs no network and no ssh. `/dev/vhost-vsock` exists on this machine.
- QMP is for hardware-level things only: screendump, key and mouse input, pause, save, balloon.
- The snapshot has a `vms` section that QML renders, like any other provider.

### Images: layered qcow2, cloud image at the bottom

```
Arch-Linux-x86_64-cloudimg.qcow2   official, pinned by sha256, cloud-init for user/keys/hostname
  packages layer                   built once from the host package list, rebuilt only when the list hash changes
    golden layer                   desktop booted healthy, guest yudaemond up
      run overlay                  one per VM, deleted on destroy
```

- The package list comes from the host: `pacman -Qqen` (~200) and `-Qqem` (~5). The guest reads the host pacman cache and the AUR helper's built packages read-only over virtiofs, so building the layer downloads almost nothing. The guest uses the same CachyOS v3 repos and `-cpu host`.
- The dotfiles repo is mounted read-only over virtiofs. An uncommitted edit shows up in the guest at once, no rebuild.

### GPU acceleration is the default: virgl (OpenGL), not Venus

- Every VM gets `virtio-gpu-gl` (virgl) on the host GPU. Host here is an RTX 3070 on the NVIDIA driver, `/dev/dri/renderD128` is present.
- **Why OpenGL and not Venus:** our whole desktop is OpenGL. Hyprland composites with GLES/GL and Qt Quick in quickshell uses OpenGL. Venus (Vulkan) adds Vulkan apps and GL 4.6 through Zink, and Collabora notes both virgl and Venus pay host/guest sync costs. Reports on a CachyOS host show virgl and Venus both slower than llvmpipe in some setups, with the host GPU stuck at idle clocks. Venus also needs a new NVIDIA proprietary driver (570.86 or later per the Mesa docs). Choose Venus per VM only for a Vulkan workload. Measure before trusting either.
- **Headless:** `-display egl-headless` renders on the host GPU without a window. Screenshots come from QMP `screendump`.
- **Human view:** `-display dbus,gl=on`. On Linux this hands the frame over as a dmabuf, zero copy.
- **Many VMs, one GPU:** each VM gets its own host GL context, so virgl behaves like several OpenGL apps on the host. The governor caps the number of GL VMs and shows it. Collabora notes virgl struggles with many concurrent GL apps, so the cap comes from a measured bench, not a guess.
- DRM native context does not exist for NVIDIA. Not an option here.
- **Cost:** a virgl device cannot be saved. UTM and Proxmox both report that save and snapshot fail with virgl, and QEMU blocks migration for it. GL VMs therefore have no RAM-to-file save.

### Sleep and wake

| tier | state | cost | wake |
| --- | --- | --- | --- |
| hot | running | full | none |
| warm | QMP `stop`, balloon inflated | RAM only, no CPU | milliseconds |
| parked | warm plus the VM's cgroup RAM reclaimed to swap | almost no RAM, no CPU | the first touches page back in, about a second |
| off | QEMU exited, overlay kept | disk only | boot from golden, a few seconds |

- **Why not save RAM to a file:** it only helps when it is cheaper than the alternatives, and for GL VMs QEMU cannot do it at all. Parked reaches the same goal on the host side: after `stop`, write to the VM cgroup's `memory.reclaim` so the kernel pages the idle guest RAM out to zram or swap. The GPU context stays valid because QEMU keeps running. Needs measuring (swap size, wake time).
- **What a RAM file would buy:** a fresh VM in about a second from a booted golden state, and one page-cache copy shared by many clones. Firecracker does it by mapping the memory file `MAP_PRIVATE`, restore in tens of milliseconds. QEMU has `mapped-ram` with multifd and direct-io for fast non-live saves, but still loads RAM up front, and the lazy userfaultfd fast-load series is not merged. So it is an optional later tier for non-GL VMs, not part of the first version.
- Idle detection: no tool call for N seconds and guest CPU near zero, then warm; warm for M minutes, then parked; parked for long, then off.
- Any tool call wakes the VM before it runs. The agent never sees sleep.
- Boot from golden stays fast through a trimmed guest: Hyprland autologin, no display manager, only the units the desktop needs. Target measured in the bench.

### Resource governor (in the daemon)

- Global budget: default half the RAM and a quarter of the cores. A new VM is admitted, queued, or makes the least recently used VM sleep. The host never swaps.
- Each VM is a systemd user scope with `MemoryMax`, `CPUQuota`, `CPUWeight`, `IOWeight`, low priority, so the desktop stays smooth. Balloon with free-page-reporting shrinks idle guests, and parking reclaims the rest.
- Meters are read in-process from cgroup files (`cpu.stat`, `memory.current`, `memory.max`), with zero spawns at steady state. Detailed sampling runs only while a client subscribes, which is the processes widget being open.

### Processes widget

A VMs section in the processes widget (`ProcessPanel`, `ProcessList`), one row per VM:
- name, tier, owning agent;
- CPU against its quota, RAM against its limit with the balloon's current size, overlay disk size, GL context;
- a header bar for the global budget: used against allowed, for RAM, CPU and GL VMs;
- the actions sleep, wake, destroy and view.

### Many agents

- **Default: one VM per agent.** Overlays and golden clones are cheap, and isolation is the point.
- **Teams:** a team gets a run id. VMs created under it share a read-only input and a write-once results directory, and show up grouped in the widget.
- **Shared VM:** several agents can attach to one VM. One holds the controller role (input), the others observe (screenshot, exec read-only). Taking over needs the holder to release it or time out. The same flag is how a human takes control.
- **Fork:** `vm_fork(name)` clones a VM's disk (and its RAM only for non-GL VMs, later) so agent B starts from agent A's exact state. Use it to try two fixes in parallel.
- **Budget fairness:** per-agent quota inside the global budget, so one agent cannot starve the others.

### How agents work on VMs

Structured state first, pixels last, a human can always look and take over.

Exposed as `yudaemond mcp` tools and the same verbs on the CLI with `--json`:
- Lifecycle: `vm_create(from, dotfiles=<ref|worktree>, cores, mem, gl)`, `vm_list`, `vm_sleep`, `vm_wake`, `vm_destroy`, `vm_snapshot`, `vm_restore`, `vm_fork`.
- Do: `vm_exec(cmd)` through the guest daemon, `vm_push`, `vm_pull`, `vm_key`, `vm_type`, `vm_click`, `vm_move`. Input goes through QMP at compositor level, so keybinds really get tested.
- See: `vm_state` (the guest daemon snapshot), `vm_ui_tree`, `hyprctl -j` through exec, `vm_screenshot`. Screenshots judge visuals only.
- Wait: `vm_wait(until=<window | surface mapped | state predicate | log pattern | exit>, timeout)`, driven by QMP events, Hyprland events and the guest daemon socket. No sleep loops, no screenshot spam.
- Verify: `vm_run_scenario(name)` runs deterministic checks first and screenshots for a vision judge last.
- Every result is bounded and typed: capped output with a handle for the rest, exit codes, durations.

Quickshell as an MCP surface is done at the daemon: `yudae ui tree` and `yudae call` work on the host and in any guest. Not in QML.

### Humans

- `vm view <name>` opens a window on the same VM (dbus dmabuf), read-only or interactive. A human and an agent can watch the same screen.
- A control flag: while a human holds input, agent input fails with "human has control".
- `vm tail` follows the console, the guest journal and the agent call log. Every call is recorded and replayable.

### Isolation and records

- User-mode networking, optional egress allowlist. Only the repo and the pacman cache are shared, both read-only. No secrets, no `$HOME`. Results leave through `vm_pull`.
- Leases with a TTL: when the agent session ends, the VM is slept, then destroyed.
- Every run writes `runs/<id>/` with the base hash, package-list hash, dotfiles ref and dirty diff, scenario, logs and screenshots, so a failure can be replayed on the same state.

### Scenarios

`vm/scenarios/<name>.json` with `context`, `steps` and `proof`. First ones: session boots healthy, lock and unlock, greeter login, launcher search and launch, workspace switch, bar unmaps in fullscreen, idle shell spawns no process.

`hypr-test` stays for fast nested checks while editing. VMs cover greetd, the lock, real session start, a clean-machine install and parallel agents.

### Host prerequisites

- Needed: `qemu-desktop` (QEMU 11.1.2), `qemu-ui-dbus`, `qemu-ui-egl-headless`, `qemu-ui-opengl`, `virtiofsd`.
- The CachyOS package databases are stale, so the install returns 404s. A refresh without a full upgrade is a partial upgrade, which Arch does not support. A full `-Syu` is 106 packages including `linux-cachyos` and the NVIDIA module (7.3.0-4 to 7.3.1-1), so it needs a reboot before the new modules load.

## 4. Single IPC entry

One command for everything that talks to the running shell and daemon:

```
yudae call <target> <method> [args...]     # -q is a quiet no-op if nothing is running
yudae state | doctor | bench | parity | ui tree
yudae vm <verb> ...                        # section 3, same as the MCP tools
```

- The daemon owns routing. A feature registers its target in its provider (`weather`, `launcher`, `bar`, `menu`, `lock`, `vms`).
- Hyprland binds, scripts, the MCP and VM scenarios all use `yudae call`, never raw `qs ipc call`.
- Changing state from a CLI pushes a refresh, no timers.
- The same command works inside a VM, because the guest runs the same yudaemond.

## 5. Order of work

1. Docs: split `AGENTS.md` into index + `agents/skills/` + `docs/`.
2. `yudae call` and the idle-spawn test as an `xmake test` item.
3. Repo restructure (section 1, steps 1 to 3).
4. xmake tasks (section 2), starting with `link`, `lint`, `build`.
5. `vm/`: copy the useful xmake pieces from playground, add the x86_64 cloud image, the host package-list layer and virtiofs dotfiles.
6. Daemon `vms` provider: QMP, vsock to the guest daemon, headless guest daemon build.
7. Governor, sleep tiers (hot, warm, parked, off), GPU limits, fork. RAM-file clones for non-GL VMs only if measured worth it.
8. MCP tools, `vm view`, control flag, run records, the processes widget section.
9. Scenarios, then CI.

## 6. Decisions

Settled:
- `hypr/` is symlinked into `~/.config`.
- Playground is merged into `vm/`, its old work is dropped.
- Vanilla QEMU. A new Linux fork only if vanilla blocks us.
- VMs are GPU accelerated.
- VM control lives in yudaemond (Zig). Go is not used.

Open:
- Full system upgrade so QEMU can be installed (section 3, prerequisites).
- Repo root name and place (`~/dotfiles`).
