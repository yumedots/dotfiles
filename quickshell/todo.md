# Agent widget — plan

Target: Quickshell topbar widget driven by OpenCode v2 server state, tracking the
Hyprland cursor, living in `~/.config/quickshell`.

## Locked decisions

| Area | Decision |
| --- | --- |
| Placement | A topbar widget, built with the house primitives (`qs` module, `ui/`, `services/`, `lib/`, `Bar.qml` wiring). Clicking it opens a panel |
| Panel | Display only. No input line, no session list, no model switcher, no separate window — the agent is talked to in the terminal it runs in |
| Panel size | The panel keeps one size, so the popup it lives in never resizes while it is open. A popup that resizes while it is open crashes quickshell |
| Cursor behavior | The topbar icon keeps its eyes still and blinks; the panel face follows the cursor and blinks |
| Cursor source | Hyprland C++ plugin (`mouseMove` event → FIFO → widget) |
| OpenCode link | Direct SSE to the OpenCode v2 server (`/api/event`), basic auth from `service.json` |
| Session scope | Aggregate across all sessions on the server. The sessions the server says are running right now (`/api/session/active`) each get a row, so several sessions working at once are all visible |
| Marks | The provider of a session gets its own svg (`assets/providers`), white, drawn at the size of the screen |
| Notification | `notify-send` → the quickshell notification daemon already running on this box |
| Subscription | The credential the CLI keeps in the server is used against the plan's own endpoint, which answers with the windows of what is left of the allowance |
| Visual | House `Figure` primitive shapes; the body is solid and the eyes are holes in it; no third-party assets |
| Spin | One speed for the bar icon and the panel face (`Config.agentSpinMs`), slow enough to read |

## Verified primitives (measured on this machine)

- OpenCode v2.0.32 background service, `~/.local/state/opencode/service.json` → `{url, password}`.
  Basic auth `opencode:<password>`; 401 without it.
- `GET /api/event` is SSE (`data: {...}` lines, 15 s heartbeat). Public events confirmed live:
  `session.status`, `session.execution.started|succeeded|failed|interrupted`, `permission.asked|replied`,
  `form.created|replied`, `session.inbox.*`, `session.viewed`, `session.created|renamed`.
- `GET /api/credential` hands over the OAuth credential the CLI is signed in with.
- `GET https://opencode.ai/zen/go/v1/usage` with that credential as a bearer token answers with
  `rolling`, `weekly`, and `monthly` windows, each with a percent and a reset time.
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
- `services/OpenCode.qml` — service.json auth, SSE stream, per-session state, aggregate state, the
  sessions that are running right now, the finish notification, the subscription windows.
- `assets/providers/` — the marks of the providers, one svg each.
- `ui/DynamicIcon.qml` — the primitive for animated vector icons: one path from any number of
  closed subpaths, odd-even holes, morphable.
- `ui/AgentFace.qml` — the face: body shape, blinking eyes, lean.
- `bar/widgets/AgentStat.qml` — the topbar widget: the face as a bar icon, eyes still.
- `tooltips/AgentPanel.qml` — the panel: the face at full size, the state, the work, the plan.
- `config.toml` — `agent*` constants.
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
- The subscription is read with the OAuth credential the server keeps. When that credential is
  refreshed the server hands over the fresh one, but a plan that is not the Go plan has no
  windows to show and the panel says so.
