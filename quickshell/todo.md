# Agent widget — v1 plan

Target: Quickshell topbar widget driven by OpenCode v2 server state, tracking the
Hyprland cursor, living in `~/.config/quickshell`.

## Locked decisions

| Area | Decision |
| --- | --- |
| Placement | A topbar widget, built with the house primitives (`qs` module, `ui/`, `services/`, `lib/`, `Bar.qml` wiring). Clicking it opens a panel |
| Cursor behavior | The topbar icon keeps its eyes still and blinks; the panel face follows the cursor and blinks |
| Cursor source | Hyprland C++ plugin (`mouseMove` event → FIFO → widget) |
| OpenCode link | Direct SSE to the OpenCode v2 server (`/api/event`), basic auth from `service.json` |
| Session scope | Aggregate across all sessions on the server |
| Input | The panel has an input line under the face, focused on open, Enter sends |
| Send target | The session the panel sends to is the most recently touched one, falling back to the newest session on the server |
| Notification | `notify-send` → the quickshell notification daemon already running on this box |
| Visual | House `Figure` primitive shapes; eyes are holes in the body; no third-party assets |
| v1 scope | State machine, cursor gaze, finish notification, type-and-send, idle animation, click-through |

## Verified primitives (measured on this machine)

- OpenCode v2.0.32 background service, `~/.local/state/opencode/service.json` → `{url, password}`.
  Basic auth `opencode:<password>`; 401 without it.
- `GET /api/event` is SSE (`data: {...}` lines, 15 s heartbeat). Public events confirmed live:
  `session.status`, `session.execution.started|succeeded|failed|interrupted`, `permission.asked|replied`,
  `form.created|replied`, `session.inbox.*`, `session.viewed`, `session.created|renamed`.
- `POST /api/session/:id/prompt` `{text}` works (probed on a throwaway session).
- Quickshell 0.3.2 / Qt 6.12. `Quickshell.Io.Process` + `SplitParser` streams SSE lines correctly
  (live probe ran; frames parsed).
- `Quickshell.Io.FileView` reads `service.json`; `watchChanges` catches service restarts.
- Hyprland 0.56.2 headers installed at `/usr/include/hyprland`, pkg-config `hyprland` resolves,
  and the installed `version.h` commit hash matches the running compositor exactly — a plugin
  built here will pass the API hash check.
- `Event::bus()->m_events.input.mouse.move` carries `Vector2D` global layout coords.
- `Quickshell.Wayland.WlrLayershell` gives `layer`, `keyboardFocus` (None/OnDemand/Exclusive),
  `namespace`; `QsWindow.mask` + `Region` (Rect/Ellipse, Combine/Subtract/Intersect/Xor) does
  click-through.
- `notify-send` exists and the bus name `org.freedesktop.Notifications` is owned by quickshell
  (pid 95053) — notifications route into the in-shell notification panel.
- `Quickshell.Shapes` (`QtQuick.Shapes`): a `ShapePath` takes several `PathSvg` subpaths in one
  path string, and the odd-even fill rule is the default, so a subpath inside another one punches
  a hole. The `fillRule` enum is not reachable from QML, and a `Repeater` cannot live inside a
  `ShapePath` — path elements are not items.
- `Window.window` gives the window, and `Window.window.contentItem` maps items into window
  coordinates. `QSWindow` is not reachable as an attached property.
- `SearchField` takes the key press before the input's own accept, so a panel that needs Enter
  has to act on the key itself.
- `Quickshell.Io.StdioCollector` signals `streamFinished` with no argument; the output is on its
  `text` property.

## Shape mapping (house `Figure` vocabulary)

| State | Body shape | Eyes |
| --- | --- | --- |
| idle | circle (exponent 2, 1 lobe) | open, blinking |
| working | spike — `Figure` version 2 (exponent 2, 9 lobes, scallop 0.16) | closed |
| blocked | triangle — `Figure` version 3 (exponent 2, 3 lobes, scallop 0.28) | open, wide |
| error | diamond — `Figure` version 9 (exponent 1) | open |

Note: the triangle is version **3** in `lib/figure.js`; version 2 is the 9-lobe spike. Mapping is
by shape, using the workspace indicator's own version table.

## Files

- `lib/agent.js` — body outline (continuous lobes, morphable), eye socket geometry, gaze math,
  cursor FIFO path.
- `services/Cursor.qml` — reads the plugin FIFO, exposes `x`/`y`.
- `services/OpenCode.qml` — service.json auth, SSE stream, per-session state, aggregate state,
  prompt sending, finish notification.
- `ui/DynamicIcon.qml` — the primitive for animated vector icons: one path from any number of
  closed subpaths, odd-even holes, morphable.
- `ui/AgentFace.qml` — the face: body shape, blinking eyes, lean.
- `bar/widgets/AgentStat.qml` — the topbar widget: the face as a bar icon, eyes still.
- `tooltips/AgentPanel.qml` — the panel: the face at full size, the state, the input line.
- `config.js` — `agent*` constants.
- `qmldir` files — register the new module entries.
- `Bar.qml` + `topbarlayout.json` — the widget slot.
- `~/.config/hypr/plugins/agent-cursor/` — Hyprland plugin source + Makefile.
- `~/.config/hypr/plugins.lua` — load the plugin, pre-allow its permission.

## Risks

- Plugin ABI: headers match the running compositor commit, so the API hash check should pass.
  Rebuild after a Hyprland upgrade.
- The plugin writes to a FIFO in the Hyprland instance's own directory, so a nested test session
  and the live one do not compete for the same stream. The compositor does not export its instance
  signature to its own environment, so the plugin finds the directory from the files it has open.
- A compositor that already loaded the plugin keeps serving the old binary from its loader cache.
  The build writes a new inode, and the config loads the `.bin` path, so a rebuilt plugin needs a
  config reload to take effect.
- Plugin FIFO is unbuffered enough to drop frames under load; cursor position is idempotent, so
  dropping is harmless.
- SSE is live-only (no replay); a server restart needs a reconnect, handled by watching
  `service.json` and restarting the curl process.
