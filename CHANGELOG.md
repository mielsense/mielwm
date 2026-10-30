# Changelog

What changed in the mielwm app, newest version first. Versions follow [semantic versioning](https://semver.org). While mielwm is below 1.0, a new minor version can change how things work.

## Unreleased

### On screen

- Switching workspaces shows the workspace numbers at the bottom of the display for a moment, with the current one filled. Turn it off in Settings > Menu bar.
- Going to a stack, or bringing another of its windows to the front, shows a strip at the top with each window's icon and title and where you are, like "2 of 4".
- Stacks can show the edges of the windows behind the front one. Set Peek edges in Settings > Layout.
- A glass style in Appearance settings. Liquid glass, the default on macOS 26, is clear and bends the edges of what is behind every panel, from the search panel to the notices. Frosted keeps the blur of earlier versions.
- VoiceOver says the workspace you switch to, the app selected in the `⌥Tab` switcher, messages like "Tidied 4 windows", and in the overview the selected window, its app and its place among the search results.
- The overview's search field, results, shortcuts sheet, key hints, toasts and the `⌥Tab` switcher are drawn by macOS itself, so Liquid glass is Apple's own and bends the canvas behind it.
- The overview's search field is a capsule, like Spotlight, with the results in their own card just below it.
- The overview's panels have the continuous corners of macOS, keys show as light capsules, and the shortcuts sheet has semibold headings.
- The `⌥Tab` switcher's highlight follows the panel's rounded corners, and its arrows to more windows are drawn chevrons.

### Workspaces and layouts

- The top gap leaves room for a status bar such as Barik or SketchyBar only on displays that have one. Without one, external displays get the same 12 point top gap as the built-in display instead of 54. Settings > Layout > Top edge also offers Same as other edges and Custom, and a number already in your config keeps working as Custom.

### Settings and the menu bar

- The menu bar item can show all workspaces, the current one only, or the icon. Turning on Work with Barik switches All workspaces to the icon.
- The menu lists each workspace with windows, with its apps' icons and a check on the current one. Click one to go there.
- The menu warns when secure input is on, since mielwm's shortcuts don't work while it is.
- Settings > Advanced links to the Configuration file page for the settings that exist only in the file.
- The Settings window looks and reads like System Settings: a search field in the sidebar that finds panes and settings, panes in groups, a header on each pane, and pictures to click for the layout, the orientation, the grid style and the menu bar item.
- Settings has new panes, so each setting is where you'd look for it: Windows, Overview, Trackpad & mouse, Menu bar, AeroSpace & Barik and About. Every setting keeps its name in the config file.
- The gaps diagram is a small desktop that redraws as you type. Pointing at a gap's field lights up that gap with its size.
- Shortcuts show as light key caps instead of boxes, and a search field in Settings > Keyboard finds one by name.
- Settings > Trackpad & mouse sets the keys you hold to move and resize windows, and how fast the overview pans and zooms. These were in the config file only.
- On macOS 26 and later, mielwm's windows use the system's current look, with the new sidebar, grouped rows and controls.
- About mielwm in the menu opens Settings > About, with the version and links to the website, docs, changelog and source.
- The welcome window lists its two permissions the way Privacy & Security does, with a badge on each one you allowed.

### Fixes

- Tidy windows from the menu bar, and other actions outside the overview, now show their message on screen. Before, it only showed in the overview.
- Messages say "1 window", not "1 windows".
- Messages and search results show the keys that work there: `⌘1` to `⌘9` for search results and `⌘⇧Z` to redo in the overview.
- Leaving macOS full screen, like a full screen video, no longer flashes two desktops side by side. mielwm leaves a full screen window alone and keeps its tile for when it comes back.
- Switching workspaces no longer flashes the old windows over the new workspace.

### Performance

- The overview uses about half the CPU while your windows sit still, and switching workspaces uses less too.
- Holding `⌃⌥` to drag a window no longer starts the overview's window pictures. With the default `⌃⌥G`, the overview can take up to 0.12 seconds longer to open while it gets fresh pictures.

## 0.1.0

Released October 27, 2026. The first release.

### Workspaces and layouts

- Workspaces 1 to 9 sit side by side on one endless canvas. `⌥1` to `⌥9` go to one, and `⌥⇧1` to `⌥⇧9` move the focused window there.
- Each workspace tiles its windows, stacks them at full size, or lets a window float where you put it.
- Gaps of 8 points between windows and 12 around the edge by default, like AeroSpace, with a separate top gap for displays other than the built-in one.
- Workspace rules send an app's windows to a fixed workspace, and floating apps always float.
- Fill, fullscreen and pin for the focused window, plus grow, shrink and swapping tiles.
- Works across several displays. The workspace you go to opens on the display under the pointer.

### The overview

- `⌃⌥G` zooms out to every window as a live picture, through a curved lens that bends the edges of the canvas.
- Type to search window titles and app names, then `Return` to go or `⇧Return` to bring the window to you.
- Pan, zoom, frame a window, tidy floating windows onto a grid, and undo or redo moves.
- A minimap of the whole canvas, and a sheet listing every key with `⌘/`.

### Keyboard, trackpad and mouse

- AeroSpace's default keys wherever AeroSpace has the same action.
- `⌥Tab` goes back to the last window, or shows a recent-windows switcher while you hold `⌥`.
- Three-finger swipes switch workspaces, with a click you can feel on Force Touch trackpads.
- `⌃⌥` with a drag moves or resizes any window, and a middle-button drag pans the canvas.

### Settings and the menu bar

- A Settings window with General, Layout & workspaces, Keyboard, Appearance and Advanced panes.
- A shortcut recorder that catches conflicts with other actions and with macOS's own shortcuts.
- A live preview of the overview on the Appearance pane, with accent colors, lens strength, background and grid.
- The menu bar shows which workspaces have windows. Pause hands every window back to macOS until you resume.
- Every setting lives in `~/.config/mielwm/config.json`, which reloads as soon as you save it and lists its errors in the menu.

### AeroSpace and Barik

- Import from AeroSpace reads your gaps, layout, rules and key bindings. The first launch imports the gaps, layout and rules on its own.
- mielwm notices a running AeroSpace and offers to quit it.
- Work with Barik lets Barik's menu bar show mielwm's workspaces, with no change to Barik.

### Windows stay safe

- Quitting, pausing or logging out puts every window back on a screen. After a crash, a small watcher does the same.
- Windows come back to their places on the canvas after a restart.
- `mielwm --unpark` brings every window back by hand, if all else fails.

### Install and performance

- A signed DMG. Every release is signed with the same identity, so macOS keeps your permissions across updates.
- The `mielwm` command controls the running app from a terminal or a script.
- About 0.01% of one CPU core and 90 MB of memory at rest.
