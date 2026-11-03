# hypr-test

Verify every Hyprland, quickshell and dotfile change with `scripts/hypr-test`. It runs a private nested Hyprland + quickshell on a worktree copy of the repo, so the real session is never touched. A change is not verified until it has been seen through it.

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
