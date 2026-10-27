# mielwm

A tiling window manager for macOS that keeps every window on one endless
canvas.

Windows tile into numbered workspaces, the way AeroSpace does it. `⌥1` to `⌥9`
switch between them, and three fingers on the trackpad swipe to the next one.
When you lose track of something, press `⌃⌥G`. The view pulls back through a
curved lens, every window shows up as a live picture, and typing a few letters
takes you to the one you meant.

It's a menu bar app, and your windows stay ordinary macOS windows. mielwm
moves them with the Accessibility API and draws the zoomed-out view with Metal
from ScreenCaptureKit pictures. Windows that aren't on screen wait in a bottom
corner of a display with one point showing, a trick borrowed from AeroSpace.

mielwm needs macOS 15 or later.

## Install

Build it with the Command Line Tools (`xcode-select --install`, no Xcode
needed):

```sh
scripts/build-app.sh --install
open ~/Applications/mielwm.app
```

`--install` quits a running mielwm first, so its windows go back on screen,
copies the new app to `~/Applications` and opens it again. `--dmg` also writes
`build/mielwm-1.0.0.dmg`.

The app is signed with a self-signed identity, not an Apple Developer ID, and
it isn't notarized. On another Mac, Gatekeeper blocks the first open. Open it
once, then allow it under System Settings > Privacy & Security > Open Anyway.

The build script makes that identity the first time it runs and keeps it in
its own keychain, `~/Library/Keychains/mielwm-dev.keychain-db`. macOS ties
permissions to the signature, so they survive rebuilds. The keychain's
password is random and sits in your login keychain, which means no other user
can sign as mielwm. A program running as you can still read it with the
`security` tool, the price of a build that never asks for your password. If
the identity can't be used, the script signs ad hoc and says so, and macOS
then asks for the permissions again after every rebuild.

To use the `mielwm` command in a terminal, go to Settings > Advanced >
Command-line tool, which links it into `~/.local/bin`. Or link it yourself:

```sh
ln -s ~/Applications/mielwm.app/Contents/MacOS/mielwm ~/.local/bin/mielwm
```

## Permissions

mielwm asks for two, both in System Settings > Privacy & Security. It needs
Accessibility to move and focus windows and to catch its shortcuts. Screen
Recording gives it the window pictures in the zoomed-out view. macOS applies
Screen Recording only after mielwm restarts, and asks again every so often.
Without it everything works, but the pictures are blank cards.

The first time it starts, mielwm shows both with a button for each.

## Before you start

Quit AeroSpace, or any other window manager. Two of them fighting over the
same windows ends badly. If AeroSpace is running, mielwm offers to quit it and
manages nothing until it's gone. Set `start-at-login = false` in
`~/.config/aerospace/aerospace.toml` so it stays gone. If SwipeAeroSpace is
running too, mielwm offers to quit both, because SwipeAeroSpace froze all
input once when mielwm's permissions changed.

Turn off "Displays have separate Spaces" under System Settings > Desktop &
Dock > Mission Control, then log out and back in. With it on, a window can't
sit across two displays. mielwm reminds you once.

Use one Space. mielwm doesn't support Spaces or native fullscreen apps.

## How it works

Every window has a place on the canvas. At 100% the camera sits on one
workspace and the real windows are wherever the canvas puts them. A workspace
is a screen-sized area of the canvas, and workspaces 1 to 9 sit in a row, so
`⌥3` always lands in the same spot.

A workspace lays its windows out one of two ways. Tiles split the screen,
keeping the gaps from Settings, and a window can't be dragged smaller than its
tile. Drag the edge between two tiles to move it. A stack shows one window at
a time at full size, like AeroSpace's accordion. Any window can also float,
which means it keeps whatever size and place you give it and stays on its
workspace.

New windows join the workspace you're on. Workspace rules send an app's
windows to a fixed workspace, and floating apps (System Settings, Calculator
and a few more by default) always float.

## Keys

These work anywhere. They're AeroSpace's defaults wherever AeroSpace has the
same action, and you can change them in Settings > Keyboard.

| Keys | Action |
| --- | --- |
| `⌃⌥G` | Zoom out to the canvas, and back. |
| `⌥1` … `⌥9` | Go to that workspace. |
| `⌥⇧1` … `⌥⇧9` | Move the window to that workspace and go with it. |
| `⌃←`, `⌃→` | Previous, next workspace. They stop at the first and last. |
| Three fingers left, right | Next, previous workspace, with a click from the trackpad. |
| `⌥/` | Tile the window. Pressed again, the tiles flip between side by side and above each other. |
| `⌥,` | Stack the workspace. |
| `⌥.` | Float the window, or tile it again. |
| `⌥` arrows | Focus the nearest window that way. In a stack, the next or previous window. |
| `⌥⇧` arrows | Swap tiles, or nudge a floating window a grid step (hold to keep going). |
| `⌥Tab`, `⌥⇧Tab` | A tap goes back to the last window. Hold `⌥` for the list and let go to switch. In a stack, the next window. |
| `⌥T` | Fill the screen, keeping the gaps. Again to put it back. |
| `⌥F` | Fullscreen, no gaps (the menu bar stays). Again to put it back. |
| `⌥O` | Pin the window so it stays put while the canvas moves. |
| `⌥-`, `⌥=` | Shrink, grow the window. |
| `⌃⌥` + drag | Move a window with the left button, resize it with the right. |
| `⌃⌥` + scroll | Zoom the canvas. Zooming out at 100% opens the overview there. |
| Middle drag | Pan the canvas. A middle click without a drag still clicks. |

`⌥0`, `⌥⇧0` and `⌥;` do nothing, so they never type º, ‚ or … by accident.

macOS swipes between full-screen apps with three fingers too, which makes the
screen bounce while you swipe. Set it to four fingers in System Settings >
Trackpad > More Gestures. Settings > Layout & workspaces has a button that
opens the page.

### In the zoomed-out view

| Keys | Action |
| --- | --- |
| Type | Search window titles and app names. Every word you type has to appear, letters together, so `fas` finds `fastfetch`. Case and accents don't matter. |
| `↑` `↓`, `Tab` `⇧Tab` | Move through the results. Without a search, `Tab` walks recent windows. |
| `⌘1` … `⌘9` | Go straight to that result. |
| `Return` | Go to the selected window. |
| `⇧Return` | Bring the selected window to where you are. |
| `Esc` | Clear the search, then go back to where you started. |
| Arrows | Select the nearest window that way. |
| `⇧` arrows | Nudge the selected window. |
| `⌘` arrows | Pan. |
| `⌘=`, `⌘-` | Zoom in, out. |
| `⌘0` | Fit every window, or every match while searching. |
| `⌘F` | Frame the selected window. |
| `⌘A` | Tidy every floating window onto the grid, grouped by app. |
| `⌘Z`, `⌘⇧Z` | Undo, redo moves and tidying. |
| `⌘⌫` | Clear the search. |
| `⌘,` | Open Settings at Appearance. |
| `⌘/` | Show every key. |

The `⌃` versions (`⌃0`, `⌃Z` and so on) and `F1` work as well, and so do
`⌃U`, `⌃W`, `⌃N` and `⌃P` in the search field.

With the pointer you can click a window to go to it and drag one to move it.
Dragging the empty canvas or scrolling with two fingers pans, and pinching or
`⌘`-scrolling zooms. Clicking the minimap jumps there, and the button next to
it tidies up.

## Settings

Choose Settings… in the menu bar menu. `mielwm settings` opens it too.

General has open at login, the workspace numbers in the menu bar, how far the
overview zooms out, whether the pointer works there, and animation. Layout &
workspaces has the layout and orientation for new windows, the gaps with a
small diagram, three-finger swipes, workspace rules, floating apps and Import
from AeroSpace. Keyboard lists every shortcut. Appearance starts with a live
preview of the zoomed-out view and has the accent color, the lens, the
background, the grid and how windows look. Advanced shows the config file,
installs the command-line tool and resets everything.

To change a shortcut, click it and press the new keys. `Esc` cancels and
`Delete` clears it. The workspace, move-to-workspace, focus and move keys each
take one row ("⌥1–9", "⌥←→↑↓"). Click the row, hold the new modifiers and press
one of its keys, and all nine or four change together. If the keys you pressed
already belong to another action, the row says which one and offers to take
them. It also warns when macOS uses the same keys, such as `⌃←` for Mission
Control.

Settings writes `~/.config/mielwm/config.json` a moment after you stop
changing something and leaves the keys it didn't touch alone, though JSON
comments get lost. Changes reach the canvas right away. Edits you make to the
file show up in the open window as soon as you save.

### Menu bar

The menu bar shows the numbers of the workspaces that have windows, with the
current one filled. Turn that off in General and you get the mielwm icon
instead. A warning sign takes its place while the config has errors.

The menu says what mielwm is doing (the current workspace and its layout,
paused, or what it's waiting for). It also has the overview, Tidy windows,
Pause mielwm, Settings, About and Quit. Paused, mielwm puts every window back
on a screen and leaves them alone until you resume.

### Importing from AeroSpace

Import from AeroSpace reads `~/.config/aerospace/aerospace.toml`, or
`~/.aerospace.toml`, shows what it found and applies it. That covers the
`[gaps]` (with the per-monitor form, where `monitor."built-in"` becomes the
built-in display's top gap) and `default-root-container-layout` (`accordion`
becomes stack). It also covers `default-root-container-orientation`,
`[[on-window-detected]]` blocks that move an app to a workspace or float it,
and the `[mode.main.binding]` keys mielwm has an action for.

On the very first start, with no `config.json` yet, mielwm imports the gaps,
layout and rules by itself and tells you. It leaves the keys out, because the
defaults already match AeroSpace's.

## Config file

`~/.config/mielwm/config.json` is read at start and again whenever it changes.
Write keys flat or nested:

```json
{
  "distortion": { "strength": 0.18 },
  "navigator:accent": "auto",
  "canvas:initial_zoom": 0.6,
  "gaps:inner_horizontal": 8,
  "layout:workspace_rules": "com.spotify.client=2,com.hnc.Discord=1",
  "keys:opt+space": "overview",
  "keys:ctrl+opt+g": "none"
}
```

- `layout:` `default` (`tiles`, `stack` or `floating`), `orientation`
  (`auto`, `horizontal` or `vertical`), `workspace_rules`, `floating_apps`
- `gaps:` `inner_horizontal`, `inner_vertical`, `outer_left`, `outer_right`,
  `outer_bottom`, `outer_top` (the built-in display), `outer_top_external`
- `distortion:` `enabled`, `strength`, `edge_scale`, `feather`,
  `transition_power`, `edge_blur`, `edge_blur_start`, `vignette`, `chromatic`
- `canvas:` `background_dim`, `grid_enabled`, `grid_style` (`dots` or `lines`),
  `grid_size`, `grid_width`, `grid_opacity`, `grid_dot_size`, `initial_zoom`,
  `min_zoom`, `max_zoom`, `zoom_step`, `auto_place`, `placement_gap`,
  `snap_enabled`, `remember_layout`, `arrange_context_grouping`,
  `arrange_size_similarity`, `arrange_resize_limit`, `minimap_enabled`,
  `minimap_width`, `minimap_height`, `minimap_margin`, `minimap_opacity`,
  `gap` (how far Fill stays from the screen edges)
- `wallpaper`, `blur`, `blur_strength`, `parallax:` `enabled`, `strength`,
  `depth`
- `input:` `pan_sensitivity`, `drag_threshold`, `scroll_factor`,
  `move_modifier` (default `ctrl+opt`), `swipe_workspaces`
- `animation:` `enabled`, `speed`, `curve` (`spring` or `bezier`)
- `navigator:` `enabled`, `labels`, `dim_unmatched`, `pointer`, `accent` (a
  hex color, a preset name like `orange` or `cyan`, or `auto` for the system
  accent), `hud_scale`, `width`, `top`, `rows`, `row_height`, `rounding`,
  `panel_opacity`, `corner_labels`
- `window:` `rounding`, `shadow`
- `menubar:workspaces`
- `keys:<chord>` takes an action name from the command line list below, or
  `none` to unbind. Write chords like `ctrl+opt+g`, `opt+shift+left` or
  `cmd+,`.

mielwm skips a file that isn't valid JSON and keeps its defaults. A bad key
costs only that key. The menu lists the errors.

The canvas layout lives in `~/Library/Application Support/mielwm/layout.json`,
so windows come back to their places after a restart.

## Command line

The binary inside the app also talks to the running copy.

```sh
mielwm                          # run the app
mielwm <action> [args]          # overview, search [text], settings, help, switch next|prev,
                                # focus|nudge|pan left|right|up|down, workspace 1-9|next|prev,
                                # move-to-workspace 1-9, layout tiles|stack|floating,
                                # zoom in|out, fit, frame, summon, land, back, fill,
                                # fullscreen, pin, grow, shrink, arrange, undo, redo, refresh
mielwm state                    # the canvas as JSON
mielwm quit                     # quit, with every window back on a screen
mielwm --unpark                 # put windows back after a crash, see below
mielwm --list-windows [--json]  # the windows mielwm can see and move
mielwm --help                   # everything, including the development tools
```

## Troubleshooting

If windows are stuck in a screen corner, mielwm didn't get to put them back.
It does that when it quits, pauses, gets Ctrl-C or `kill`, or you log out.
When it crashes, a small watcher process puts them back from `layout.json`.
If even that failed, run `mielwm --unpark`.

If shortcuts do nothing, check Accessibility for mielwm. After an ad hoc
signed rebuild, remove mielwm from the list and add it again.

Blank window pictures mean Screen Recording is missing or was granted without
a restart. Quit mielwm and open it again.

If windows jump back after you move them, something else is moving them too,
like AeroSpace, Rectangle or an app with its own window handling.

Some windows can't be managed at all, such as certain dialogs and fixed panels.
`mielwm --list-windows` shows what mielwm sees.

## Development

```sh
swift build && swift test     # build and run the tests
scripts/system-test.sh        # opens throwaway windows and checks parking,
                              # unparking, adoption and quitting end to end
scripts/benchmark.sh          # CPU and memory, see docs/benchmark.md
swift scripts/make-icon.swift # redraws the app icon and menu bar glyph
```

None of these touch your own windows. `mielwm snapshot` draws any state of the
zoomed-out view to a PNG from made-up windows. `mielwm --settings-preview`
saves every Settings pane, the onboarding and the menu as PNGs in light and
dark mode, and `--selftest` drives the Settings window through its controls.
`mielwm --manage-only <pid>` manages one app's windows only, with no shortcuts
and no focus changes, and the system test drives it over its own socket.
`MIELWM_SOCKET`, `MIELWM_CONFIG_DIR` and `MIELWM_TEST_OVERLAY=1` keep a test
copy apart from the one you use. `mielwm --help` lists every option.

## License

mielwm is under the MIT License, see [LICENSE](LICENSE). It includes code
adapted from [Phantomat](https://github.com/kaolti/phantomat), which is under
the BSD 3-Clause License. [NOTICE](NOTICE) has that license and says which
parts.
