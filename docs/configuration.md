# Configuration file

Every setting lives in one JSON file that you can edit by hand or through Settings.

The file is `~/.config/mielwm/config.json`. mielwm reads it when it starts and again whenever it changes, so edits apply as soon as you save. Settings writes the same file. A key you leave out keeps its default, so a short file is normal.

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

If the file isn't valid JSON, mielwm keeps its defaults and shows the error in the menu bar. A key with a bad value is skipped on its own, and a value outside a setting's range is clamped to the nearest one that works.

## Layout and gaps

| Key | Default | What it does |
| --- | --- | --- |
| `layout:default` | `"tiles"` | The layout new windows join: `tiles`, `stack` or `floating`. |
| `layout:orientation` | `"auto"` | Tiles side by side (`horizontal`), above each other (`vertical`), or by the display's shape (`auto`). |
| `layout:workspace_rules` | `""` | `bundle.id=N` pairs, comma separated: that app's windows open on workspace N. |
| `layout:floating_apps` | System Settings, Activity Monitor, Calculator, Archive Utility | Bundle ids, comma separated, whose windows always float. |
| `layout:cross_workspaces` | `false` | Focus and move keys go on into the next workspace at the edge, instead of stopping. |
| `layout:auto_back_and_forth` | `false` | The key of the workspace you're on takes you to the one before. `mielwm workspace N` and Barik stay put. |
| `gaps:inner_horizontal` | `8` | Points between tiles side by side. |
| `gaps:inner_vertical` | `8` | Points between tiles above each other. |
| `gaps:outer_left`, `gaps:outer_right`, `gaps:outer_bottom` | `12` | Points between the tiles and the screen edge. |
| `gaps:outer_top` | `12` | The top gap on the built-in display. |
| `gaps:outer_top_external` | `54` | The top gap on other displays, with room for a status bar. |
| `canvas:gap` | `12` | How far Fill (`⌥T`) stays from the screen edges. |

## Window rules

A window rule floats a window or sends it to a workspace by its app's name or its title, like AeroSpace's `on-window-detected`. Give each rule a name and the fields it needs:

```json
{
  "rules": {
    "firefox-pip": { "app_id": "org.mozilla.firefox", "title": "Picture-in-Picture", "floating": true },
    "zoom": { "app": "^zoom", "workspace": 3 }
  }
}
```

| Field | What it does |
| --- | --- |
| `app` | A regular expression found anywhere in the app's name, ignoring case. |
| `title` | The same for the window's title. |
| `app_id` | The app's bundle id, exactly. |
| `floating` | `true` makes the window float. |
| `workspace` | `1` to `9`: the window opens on that workspace. |

A window has to match every matcher a rule has. A rule with no matcher, or with neither `floating` nor `workspace`, does nothing and never hides a later rule. When several rules match, the first by name wins, with numbers in order, so `rule-2` comes before `rule-10`. Rules apply when a window first appears, so a title that changes later doesn't move it. They come before `layout:floating_apps` and `layout:workspace_rules`.

Flat keys work too: `"rules:firefox-pip:title": "Picture-in-Picture"`. Settings doesn't edit window rules yet, so they live only in this file.

## Input

| Key | Default | What it does |
| --- | --- | --- |
| `input:swipe_workspaces` | `true` | Three-finger swipes switch workspaces. |
| `input:move_modifier` | `"ctrl+opt"` | Held with a drag to move or resize a window anywhere. |
| `input:pan_sensitivity` | `1` | How far the canvas moves per pan. |
| `input:drag_threshold` | `10` | Points a middle-button press travels before it pans instead of clicking. |
| `input:scroll_factor` | `1` | How fast the wheel zooms. |
| `navigator:pointer` | `true` | Clicks, drags, scrolls and hover work in the overview. |

## The overview

| Key | Default | What it does |
| --- | --- | --- |
| `canvas:initial_zoom` | `0.72` | The farthest the overview zooms out when it opens. |
| `canvas:min_zoom`, `canvas:max_zoom` | `0.05`, `2.5` | Zoom limits. |
| `canvas:zoom_step` | `0.12` | One zoom step with `⌘=` and `⌘-`. |
| `navigator:enabled` | `true` | The search field and its results. |
| `navigator:labels` | `true` | The name of the selected window. |
| `navigator:dim_unmatched` | `0.7` | How much windows that don't match a search fade. |
| `navigator:accent` | `"auto"` | `auto` (the system accent), a preset name (`orange`, `amber`, `yellow`, `lime`, `green`, `mint`, `teal`, `cyan`, `sky`, `blue`, `indigo`, `violet`, `purple`, `magenta`, `pink`, `red`, `white`), or `#rrggbb`. |
| `navigator:hud_scale` | `1` | The size of the search field, results and hints. |
| `navigator:width` | `680` | Width of the search field in points. |
| `navigator:top` | `0.1` | Where it sits, as a share of the screen height. |
| `navigator:rows` | `6` | How many results show. |
| `navigator:row_height` | `44` | Height of a result row. |
| `navigator:rounding` | `8` | Corner radius of rows and pills. |
| `navigator:panel_opacity` | `0.8` | Opacity of the search panel. |
| `navigator:corner_labels` | `false` | A small readout of zoom, window count and display. |
| `canvas:minimap_enabled` | `true` | The minimap. |
| `canvas:minimap_width`, `canvas:minimap_height` | `240`, `150` | Its size. |
| `canvas:minimap_margin`, `canvas:minimap_opacity` | `24`, `0.8` | Its distance from the corner and opacity. |

## The lens and the background

| Key | Default | What it does |
| --- | --- | --- |
| `distortion:enabled` | `true` | The curved lens. |
| `distortion:strength` | `0.14` | How strongly it bends. Below zero it bends inward. |
| `distortion:edge_scale` | `1.08` | How far the canvas extends under the bent edge. |
| `distortion:feather`, `distortion:transition_power` | `0.025`, `1` | How the bend fades in at the edge and over the zoom. |
| `distortion:edge_blur`, `distortion:edge_blur_start` | `0`, `0.45` | Blur toward the edges, and where it starts. |
| `distortion:vignette`, `distortion:chromatic` | `0`, `0` | Darkened corners and color fringing. |
| `wallpaper` | `true` | Your desktop picture behind the canvas. |
| `canvas:background_dim` | `0.35` | How much the background darkens. |
| `blur`, `blur_strength` | `false`, `0.7` | Blur the background, and how much. |
| `canvas:grid_enabled` | `true` | The grid on the canvas. |
| `canvas:grid_style` | `"dots"` | `dots` or `lines`. |
| `canvas:grid_size`, `canvas:grid_width`, `canvas:grid_opacity`, `canvas:grid_dot_size` | `80`, `1`, `0.1`, `2.5` | Its spacing, line width, opacity and dot size. |
| `parallax:enabled`, `parallax:strength`, `parallax:depth` | `true`, `0.06`, `0.12` | The background moving a little slower than the canvas. |
| `window:rounding`, `window:shadow` | `10`, `true` | Window corners and shadows in the overview. |

## Placement and tidying

| Key | Default | What it does |
| --- | --- | --- |
| `canvas:auto_place` | `true` | A floating window found off screen gets a free spot near the camera. |
| `canvas:placement_gap` | `40` | Space it keeps from other windows. |
| `canvas:snap_enabled` | `true` | Moved and tidied windows snap to the grid. |
| `canvas:remember_layout` | `true` | Windows come back to their places after a restart. |
| `canvas:arrange_context_grouping` | `true` | Tidying groups windows by what they're for. |
| `canvas:arrange_size_similarity`, `canvas:arrange_resize_limit` | `0.12`, `0.15` | How alike sizes must be to share a row, and how much tidying may resize. |

## Animation and the menu bar

| Key | Default | What it does |
| --- | --- | --- |
| `animation:enabled` | `true` | Camera flights. Off, mielwm cuts. |
| `animation:speed` | `1` | 1 flies in 0.8 seconds, 2 in 0.4. |
| `animation:curve` | `"spring"` | `spring` or `bezier`. |
| `menubar:workspaces` | `true` | Workspace numbers in the menu bar instead of the icon. |
| `integrations:barik` | `false` | [Barik](aerospace.md#barik) shows mielwm's workspaces. Turn it on in Settings, which also edits Barik's config. |

## Shortcuts

`keys:<chord>` binds a chord to an action. Write chords as modifiers and a key joined by `+`: `ctrl+opt+g`, `opt+shift+left`, `cmd+,`. Modifiers are `ctrl`, `opt`, `cmd` and `shift`. Set a chord to `"none"` to unbind a default.

```json
{
  "keys:opt+space": "overview",
  "keys:ctrl+opt+g": "none",
  "keys:opt+shift+f": "layout floating"
}
```

The action names are the same as the [command line](command-line.md) ones.

## The layout file

mielwm remembers where your windows sit in `~/Library/Application Support/mielwm/layout.json`, so they come back to their spots after a restart. It writes that file on its own, and you never need to edit it. If windows keep coming back in strange places, quit mielwm, delete the file and open mielwm again.
