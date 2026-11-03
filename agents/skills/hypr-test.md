# hypr-test

Verify UI and dotfile changes in a VM first: `scripts/vm-test start`, `restart`, `shot`. The guest boots the same quickshell from the read-only repo mount, so a host edit is live after `vm-test restart`, and the screenshot comes from the guest at full resolution. `scripts/hypr-test` stays for a fast nested loop while editing; it is not the proof.

`scripts/hypr-test` runs a private nested Hyprland + quickshell on a worktree copy of the repo, so the real session is never touched.

## Rules

- Edit files in the repo. Test only through `scripts/hypr-test`, never with `hyprctl` or input against the real session, except the final smoke test the user explicitly allows (`wtype` and `hyprctl dispatch movecursor` only).
- Always stop the instance when done.

## Commands

- `scripts/hypr-test start` - nested Hyprland + quickshell on the worktree copy. Fails if one is already running.
- `scripts/hypr-test shot` - screenshot of the test instance, prints the png path.
- `scripts/hypr-test run <cmd...>` - run hyprctl/qs/ipc against the test instance only.
- `scripts/hypr-test stop` - kill it and remove the worktree.
- `scripts/hypr-test list` / `gc [--all]` - live instances, cleanup.

## Loop

Shot, act via run, shot, verify. On errors the script prints the quickshell log; read it instead of guessing. If the image cannot be seen, hand the png to a vision subagent instead of guessing.
