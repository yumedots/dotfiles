# todos

State as of the yudaemond port. Branch `yudaemond`, repo `/home/gabriel/.config`.

## Open

Nothing open.

## Verify each port

```
cd quickshell/yudaemond && zig build test        # 145 tests
zig build && systemctl --user restart yudaemond
yudaemond state | jq .launcher                   # whatever you touched
yudaemond doctor                                 # providers, plus config keys nothing reads
yudaemond parity
ln -sfn ~/.config/quickshell /tmp/qmlimport/qs
/usr/lib/qt6/bin/qmllint -I /tmp/qmlimport <files>   # exit 0, unqualified warnings are noise
scripts/hypr-test start|shot|run|stop            # worktree copy: restart after every edit
```

## Gotchas that cost time

- `hypr-test` copies the tree at start: edits after `start` are invisible to the
  nested session. Always restart the instance after editing QML, or verify in the
  real session.
- A QML file missing `import qs.services` silently kills the widget (`Yudae is
  not defined`) - check the instance log, not the screenshot.
- `std.Io.Reader.readSliceShort` blocks until the buffer is full; stream with
  `readVec` or `poll`+`read`.
- Never `hub.publish()` under a provider mutex; `sample()` must unlock first.
- `quickshell/cache/launcher/*.txt` are the launcher's state files (pins, usage,
  saved), written with `{id}\t{count}\t{last}` / `name\tcommand`.
