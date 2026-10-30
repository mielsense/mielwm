# Configuration file

Every setting lives in one JSON file that you can edit by hand or through Settings.

## The file

The file is `~/.config/mielwm/config.json`. mielwm reads it when it starts and again whenever it changes, so edits apply as soon as you save. Settings writes the same file, and Settings > Advanced > Config file opens it.

A key you leave out keeps its default, so a short file is normal:

```json
{
  "layout:default": "tiles",
  "gaps:inner_horizontal": 8,
  "layout:workspace_rules": "com.spotify.client=2,com.hnc.Discord=1",
  "distortion": { "strength": 0.18 },
  "navigator:accent": "cyan",
  "keys:opt+space": "overview",
  "keys:ctrl+opt+g": "none"
}
```

Keys can be flat, like `"distortion:strength": 0.18`, or nested, like `"distortion": { "strength": 0.18 }`. Both mean the same.

### Errors

If the file isn't valid JSON, mielwm keeps its defaults and the menu bar item turns into a warning sign. A key with a bad value or an unknown name is skipped on its own and the rest still apply. Settings > Advanced and the menu's Config has problems… list each error. A number outside a setting's range is clamped to the nearest one that works.

### How Settings writes it

Settings leaves keys it didn't touch alone, but JSON comments get lost. A setting changed back to its default disappears from the file.

## Layout and workspaces

| Key | Type | Default | What it does |
| --- | --- | --- | --- |
| `layout:default` | text | `"tiles"` | The layout of a new workspace: `tiles`, `stack` or `floating`. |
| `layout:orientation` | text | `"auto"` | Tiles side by side, `horizontal`, above each other, `vertical`, or by the display's shape, `auto`. |
| `layout:stack_peek` | number, 0 to 16 | `0` | Points the windows behind a stack's front one move aside, so their edges show. |
| `layout:floating_apps` | text | System Settings, Activity Monitor, Calculator, Archive Utility | Bundle ids, comma separated, whose windows always float. |
| `layout:workspace_rules` | text | `""` | `bundle.id=N` pairs, comma separated: that app's windows open on workspace N. |
| `layout:cross_workspaces` | true or false | `false` | Focus and move keys go on into the next workspace at the edge, instead of stopping. |
| `layout:auto_back_and_forth` | true or false | `false` | The key of the workspace you're on takes you to the one before. `mielwm workspace N` and menu bar apps stay put. |
| `rules` | object | none | Window rules by app name, bundle id or title. See [Window rules](window-rules.md). |

## Gaps

| Key | Type | Default | What it does |
| --- | --- | --- | --- |
| `gaps:inner_horizontal` | number, 0 to 200 | `8` | Points between tiles side by side. |
| `gaps:inner_vertical` | number, 0 to 200 | `8` | Points between tiles above each other. |
| `gaps:outer_left`, `gaps:outer_right`, `gaps:outer_bottom` | number, 0 to 400 | `12` | Points between the tiles and the screen edge. |
| `gaps:outer_top` | number, 0 to 400 | `12` | The top gap. In Custom, only on the built-in display. |
| `gaps:outer_top_external` | text or number | `"auto"` | The top edge. `"auto"` adds the height of a status bar found along the top, `"same"` uses only `gaps:outer_top`, and a number is Custom: the top gap on every display but the built-in one. |
| `canvas:gap` | number, 0 to 200 | `12` | How far Fill, `⌥T`, stays from the screen edges. |

[Layouts and gaps](layouts.md#the-top-edge) explains the top edge modes.

## Input

| Key | Type | Default | What it does |
| --- | --- | --- | --- |
| `input:swipe_workspaces` | true or false | `true` | Three-finger swipes switch workspaces. |
| `input:move_modifier` | text | `"ctrl+opt"` | Held with a drag to move or resize a window anywhere. Any of `ctrl`, `opt`, `cmd` and `shift`, joined by `+`. |
| `input:pan_sensitivity` | number, 0.05 to 5 | `1` | How far the canvas moves per pan. |
| `input:scroll_factor` | number, 0.05 to 10 | `1` | How fast the wheel zooms. |
| `input:drag_threshold` | number, 0 to 100 | `10` | Points a middle-button press travels before it pans instead of clicking. |
| `navigator:pointer` | true or false | `true` | Clicks, drags, scrolls and hover work in the overview. |

## The overview

| Key | Type | Default | What it does |
| --- | --- | --- | --- |
| `canvas:initial_zoom` | number, 0.05 to 0.95 | `0.72` | The farthest the overview zooms out when it opens. |
| `canvas:min_zoom` | number, 0.01 to 1 | `0.05` | The farthest you can zoom out. |
| `canvas:max_zoom` | number, 1 to 10 | `2.5` | The closest you can zoom in. |
| `canvas:zoom_step` | number, 0.01 to 1 | `0.12` | One zoom step with `⌘=` and `⌘-`. |
| `navigator:enabled` | true or false | `true` | The search field and its results. |
| `navigator:labels` | true or false | `true` | The name of the selected window. |
| `navigator:dim_unmatched` | number, 0 to 1 | `0.7` | How much windows that don't match a search fade. |
| `navigator:corner_labels` | true or false | `false` | A small readout of zoom, window count and display. |
| `canvas:minimap_enabled` | true or false | `true` | The minimap. |
| `canvas:minimap_width`, `canvas:minimap_height` | number | `240`, `150` | Its size in points, 80 to 800 wide and 60 to 600 tall. |
| `canvas:minimap_margin` | number, 0 to 200 | `24` | Its distance from the corner. |
| `canvas:minimap_opacity` | number, 0 to 1 | `0.8` | Its opacity. |

## Panels and color

| Key | Type | Default | What it does |
| --- | --- | --- | --- |
| `navigator:accent` | text | `"auto"` | `auto` for the system accent, a preset name, or `#rrggbb`. The presets are `orange`, `amber`, `yellow`, `lime`, `green`, `mint`, `teal`, `cyan`, `sky`, `blue`, `indigo`, `violet`, `purple`, `magenta`, `pink`, `red` and `white`. |
| `appearance:glass` | text | `"liquid"` | What panels are made of: `liquid` or `frosted`. Before macOS 26 they are always frosted. |
| `navigator:hud_scale` | number, 0.5 to 2 | `1` | The size of the search field, results and hints. |
| `navigator:width` | number, 360 to 1400 | `680` | Width of the search field in points. |
| `navigator:top` | number, 0 to 0.5 | `0.1` | Where it sits, as a share of the screen height. |
| `navigator:search_height` | number, 36 to 110 | `56` | Height of the search field. |
| `navigator:rows` | number, 3 to 12 | `6` | How many results show. |
| `navigator:row_height` | number, 36 to 96 | `44` | Height of a result row. |
| `navigator:query_size`, `navigator:title_size`, `navigator:detail_size` | number | `24`, `13`, `12` | Text sizes of the search text, result titles and their details. |
| `navigator:label_size`, `navigator:corner_size` | number | `12`, `12` | Text sizes of window names and the corner readout. |

## The lens and the background

| Key | Type | Default | What it does |
| --- | --- | --- | --- |
| `distortion:enabled` | true or false | `true` | The curved lens. |
| `distortion:strength` | number, -0.5 to 0.5 | `0.14` | How strongly it bends. Below zero it bends inward. |
| `distortion:edge_scale` | number, 1 to 1.5 | `1.08` | How far the canvas extends under the bent edge. |
| `distortion:feather` | number, 0 to 0.25 | `0.025` | How softly the bend fades in at the edge. |
| `distortion:transition_power` | number, 0.1 to 8 | `1` | How the bend grows as you zoom out. |
| `distortion:edge_blur`, `distortion:edge_blur_start` | number | `0`, `0.45` | Blur toward the edges, 0 to 1, and where it starts, 0 to 0.95. |
| `distortion:vignette` | number, 0 to 1 | `0` | Darkened corners. |
| `distortion:chromatic` | number, 0 to 1 | `0` | Color fringing at the edges. |
| `wallpaper` | true or false | `true` | Your desktop picture behind the canvas. |
| `canvas:background_dim` | number, 0 to 0.9 | `0.35` | How much the background darkens. |
| `blur` | true or false | `false` | Blur the background. |
| `blur_strength` | number, 0 to 1 | `0.7` | How much. |
| `canvas:grid_enabled` | true or false | `true` | The grid on the canvas. |
| `canvas:grid_style` | text | `"dots"` | `dots` or `lines`. |
| `canvas:grid_size` | number, 24 to 400 | `80` | Grid spacing in points. Moved and tidied windows snap to it. |
| `canvas:grid_width`, `canvas:grid_dot_size` | number | `1`, `2.5` | Line width, 1 to 8, and dot size, 2 to 16. |
| `canvas:grid_opacity` | number, 0 to 0.5 | `0.1` | How strong the grid is. |
| `parallax:enabled` | true or false | `true` | The background moves a little slower than the canvas. |
| `parallax:strength`, `parallax:depth` | number | `0.06`, `0.12` | How much, 0 to 0.5, and how deep it feels, 0 to 1. |
| `window:rounding` | number, 0 to 40 | `10` | Window corners in the overview. |
| `window:shadow` | true or false | `true` | Window shadows in the overview. |

## Placement and tidying

| Key | Type | Default | What it does |
| --- | --- | --- | --- |
| `canvas:remember_layout` | true or false | `true` | Windows come back to their places after a restart. |
| `canvas:auto_place` | true or false | `true` | A floating window found off screen gets a free spot near the camera. |
| `canvas:placement_gap` | number, 0 to 400 | `40` | Space it keeps from other windows. |
| `canvas:snap_enabled` | true or false | `true` | Moved and tidied windows snap to the grid. |
| `canvas:arrange_context_grouping` | true or false | `true` | Tidying groups windows by what they're for. |
| `canvas:arrange_size_similarity` | number, 0 to 0.5 | `0.12` | How alike sizes must be to share a row when tidying. |
| `canvas:arrange_resize_limit` | number, 0 to 0.5 | `0.15` | How much tidying may resize a window. |

## Animation, menu bar and apps

| Key | Type | Default | What it does |
| --- | --- | --- | --- |
| `animation:enabled` | true or false | `true` | Camera flights. Off, mielwm cuts. |
| `animation:speed` | number, 0.2 to 8 | `1` | 1 flies in 0.8 seconds, 2 in 0.4. |
| `animation:curve` | text | `"spring"` | `spring` or `bezier`. |
| `menubar:style` | text | `"all"` | What the menu bar item shows: `all` workspaces with windows, the `current` one only, or the `icon`. The older `"menubar:workspaces": false` still means `icon`. |
| `notices:workspace` | true or false | `true` | The workspace pill shows at the bottom of the display for a moment after you switch. |
| `integrations:barik` | true or false | `false` | A supported menu bar app shows mielwm's workspaces. Turn it on in Settings, which also edits the app's config. See [AeroSpace-compatible apps](compatible-apps.md). |

## Shortcuts

`keys:<chord>` binds a chord to an action. Write chords as modifiers and a key joined by `+`: `ctrl+opt+g`, `opt+shift+left`, `cmd+,`. Modifiers are `ctrl`, `opt`, `cmd` and `shift`. Set a chord to `"none"` to unbind a default, or to `"noop"` to have it do nothing at all, so the key never reaches an app.

```json
{
  "keys:opt+space": "overview",
  "keys:ctrl+opt+g": "none",
  "keys:opt+shift+f": "layout floating",
  "keys:opt+b": "workspace-back-and-forth",
  "keys:opt+shift+equal": "resize smart +100"
}
```

The action names are the same as the [command line](command-line.md#actions) ones. By default `⌥0`, `⌥⇧0` and `⌥;` are `noop`, so they never type º, ‚ or … by accident.

## The layout file

mielwm remembers where your windows sit in `~/Library/Application Support/mielwm/layout.json`, so they come back to their spots after a restart. It writes that file on its own, and you never need to edit it. If windows keep coming back in strange places, quit mielwm, delete the file and open mielwm again.
