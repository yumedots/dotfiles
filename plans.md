# Plans

## 1. Disk & fs

A disk treemap like Omarchy's disktree, built on the VM app primitive: daemon scans, Quickshell draws. The same backend is the file manager's index later; only its front end waits.

### Rules

- A scan runs only when asked. No scan on open, no idle scan, no background walk.
- Polkit is the only privilege path, for the app and for `yudae` CLI alike. No pkexec, no sudo, no root flag on the user daemon.
- Denied or no agent means the scan fails and says so. There is no partial scan.
- Protected paths are never walked and never appear: `/proc /sys /dev /run`, every mount point, `/usr /etc /boot /efi /bin /sbin /lib*`, `/var/lib/pacman`, `/var/lib/systemd`. The free space bar still reads the real disk.

### Privilege

`yudae-fsd` is the same binary under a subcommand, run as root by a systemd socket unit at `/run/yudae/fsd.sock`. The user daemon connects, the helper reads peer credentials and a pidfd from the socket, and asks polkit `CheckAuthorization` per action, which raises the session agent's prompt.

| action | auth |
| --- | --- |
| `org.yudae.fs.scan` | admin, remember ~5 min |
| `org.yudae.fs.remove` | admin, every time |
| `org.yudae.fs.bench` | admin, drop caches for cold runs |
| `org.yudae.packages.manage` | admin, every time |

The helper re-checks the protected list and resolves paths with `openat2(RESOLVE_NO_SYMLINKS | RESOLVE_NO_XDEV)`, so a bad caller or a symlink swap cannot escape. Polkit and systemd files are written as root only after asking.

### Scanner

One flat array of nodes, names in one buffer, no full paths: parent, first child and next sibling indexes, size, name offset and length, category and flags. Small files fold into one node per directory; only directories and big files get their own. Hardlinks counted once. btrfs reports a per-subvolume id, so subvolumes of one disk count as one and other filesystems are skipped.

Versions are benchmarked, the fastest that passes exact accuracy ships, the rest is deleted:

| id | how |
| --- | --- |
| V0 | one thread, `readdir` + `fstatat` |
| V1 | thread pool, raw `getdents64`, small `statx` |
| V2 | V1 with batched `statx` over io_uring |
| V3 | btrfs `TREE_SEARCH_V2`, only if V1/V2 still fall short |

Cache file `~/.cache/yudae/disk.bin`, mode `0600`, laid out for `mmap` with totals already summed so a view loads without walking, written to a temp file and renamed. Old map shows instantly while the fresh scan runs.

Optional live map: after a scan the helper watches each subvolume with fanotify `FAN_MARK_FILESYSTEM | FAN_REPORT_DFID_NAME` and updates only the changed directories. It never scans on its own.

### Benchmark

`xmake bench disk` runs `yudaemond bench disk` on the existing harness: `bench/disk.jsonl`, deltas against `bench/baseline.json`, nonzero exit on a missed gate. Why a number moved, not how big it is.

- Versions V0 to V3 at 1/2/4/8/16/nproc threads, warm and cold page cache.
- Fixtures: a seeded synthetic tree (deep, wide, 1M tiny files, hardlinks, sparse, symlink loop, nested subvolume, bind mount) with exact expected answers, then `~` and the whole disk.
- Speed: entries/s, syscalls per entry, user and system time, peak RSS, bytes per node, and per phase: `getdents`, `statx`, queue wait, idle threads, merge, size roll-up, cache write.
- Views: query p50/p99, snapshot bytes. Cache: file size, `mmap` load and verify time.
- Accuracy: every synthetic directory total exact; every top folder on real data exact against `du -sx --block-size=1`; the gap between disk used and scanned total reported as unaccounted.
- fanotify: 100k change storm, per-change latency, events/s, overflow handling (rescans only the affected directory), CPU at idle ~0, and the live map must equal a fresh scan byte for byte.
- Reference scanners ncdu, gdu, dua and hyperfine are installed with root at bench time, after asking. Gates come from the first measured run, then tighten. Accuracy gates are always exact.

### Surface

- fs provider: `scan`, `view{path, depth, topN}`, `search`, `stat`, `mark`, `unmark`, `trash`, `delete`, `move`, `copy`, `rename`. Root-owned paths go through the helper.
- Snapshot key `disk` carries the focused view only, a few KB at any disk size; the treemap layout is computed in Quickshell.
- CLI `yudae disk scan|view|mark|remove|clean|uninstall`, the same MCP tools, `docs/daemon.md`, `docs/agent-tooling.md`, `docs/perf.md`.

### Packages and caches

- pacman and paru from `/var/lib/pacman/local/*/desc`, no exec: name, version, size, explicit or dependency, orphan, AUR or repo. flatpak from `flatpak list`, unused runtimes included.
- Uninstall `pacman -Rns` and system flatpak through the helper; user flatpak direct. Always behind a confirm naming every item and the space returned.
- Caches table in Zig, each a path plus its tool command when one exists: `paccache` for the 16G pacman cache, paru clones, npm, bun, cargo registry, go modcache, rustup, zig, mesa shaders, thumbnails, pip/uv, journal, coredumps, trash, and our own `~/.cache/yudae-*` and `rootfs-build` VM builds (~45G today). Project build output found by the scan (`target/`, `node_modules/`, `.zig-cache`, `zig-out`, `.venv`) gets the hatch.

### App

`shell/app-disk.qml`, AppId `com.yudae.disk`, on `AppWindow`: Map, Packages, Caches. Colors from `Config.qml`, glyph from the icon list, launcher entry with the same glyph. No key hints on screen.

### Order of work

1. Scanner core, benchmarking, pick the winning version.
2. Cache file.
3. `yudae-fsd`, polkit and systemd units (ask before writing as root).
4. fanotify live map and its bench.
5. fs provider, snapshot key, CLI and MCP.
6. Packages and caches.
7. Docs.
8. Quickshell app.

### Tests

One Zig test on a temp tree: totals, hardlinks once, a protected path never appears and refuses removal, a symlink escape refused, cache file round-trip. VM scenario for a scan with polkit denied and no agent.

Settled: fastest measured scanner ships; cache file is the only thing on disk; protected paths invisible in scan and app; polkit for every privileged action; backend first, front end later.
