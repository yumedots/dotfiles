# drop-preview

Hyprland plugin: while you drag a tiled window with the mouse, a dark box with a gray
border shows where it will land.

Built for Hyprland **0.57.0** (`0aa6745`). Plugins are ABI-locked: run `make` after every
Hyprland update.

## Behaviour

- Mouse only: appears while a mouse button is held. Touch, tablet and bind-only drags are ignored.
- dwindle: exact. Runs the same steps as release (`dragEnd` -> `changeFloatingMode` ->
  `CDwindleAlgorithm::addTarget` -> `CWindowTarget::updatePos`), including `smart_split`,
  `precise_mouse_move`, `preserve_split`, `split_bias`, `default_split_ratio`,
  `split_width_multiplier`, `use_active_for_splits`, preselect, gaps and workspace gap rules.
- groups: `group:drag_into_group = 1` highlights the group you hover.
- master / scrolling / monocle: approximate, highlights the tiled window under the cursor.
- Floating windows get no preview, they stay where you drop them.
- Drawn just behind the dragged window, above the rest, full monitor damage, edges snapped to
  whole pixels, so the box slides without jitter.

## Build

```sh
make
```

## Config

`~/.config/hypr/drop-preview.lua`, required from `plugins.lua`.

| key | default | meaning |
| --- | --- | --- |
| `enabled` | `true` | on/off |
| `col.border` | `rgba(909090ff)` | gray outline |
| `col.fill` | `rgba(20202066)` | dark translucent inside |
| `border_size` | `-1` | `-1` = follow `general:border_size` |
| `rounding` | `-1` | `-1` = follow `decoration:rounding` |
| `blur` | `false` | blur behind the fill |
| `animation_speed` | `0` | `0` = snap instantly, higher = slide |
| `generic_fallback` | `true` | highlight hovered window on non-dwindle layouts |
| `spacing` | `8` | inset from the drop area in logical px, `0` = exact size |

`rounding = -1` and `border_size = -1` track Hyprland live: changing `decoration:rounding`
or `general:border_size` changes the preview immediately.

## Test harness

`test/harness.cpp` is a test-only plugin. Never load it in a real session. It performs
synthetic drags inside the `vm-test` guest and compares `predictDrop()`
with where Hyprland actually places the window; it also holds a drag open for screenshots
and reports the resolved rounding/border values. Results go to `/tmp/dp-results.txt`.

Updating the binary: `hyprctl plugin unload <path>` then `hyprctl plugin load <path>`. A plain `hyprctl reload` will not re-add a config-loaded plugin after unloading it (Hyprland only loads config plugins at startup), and its config keys then log as unknown.

Loading twice is a no-op, so a manual load plus the config load cannot double-draw.

Verified: 584/584 drops exact across default, `preserve_split`, `smart_split`,
`precise_mouse_move`, `split_bias` + ratio 1.3 + custom gaps; rounding follows `0 -> 18`;
border follows `2 -> 6`; preview slides monotonically with no edge jitter.
