# Changelog

What changed in the mielwm app, newest version first. Versions follow [semantic versioning](https://semver.org). While mielwm is below 1.0, a new minor version can change how things work.

## Unreleased

### On screen

- Switching workspaces shows the workspace numbers at the bottom of the display for a moment, with the current one filled. Turn it off in General settings.
- Going to a stack, or bringing another of its windows to the front, shows a strip at the top with each window's icon and title and where you are, like "2 of 4".
- Stacks can show the edges of the windows behind the front one. Set Peek edges in Layout & workspaces settings.
- A glass style in Appearance settings. Liquid glass, the default on macOS 26, is clear and bends the edges of what is behind every panel, from the search panel to the notices. Frosted keeps the blur of earlier versions.
- VoiceOver says the workspace you switch to and the app selected in the `⌥Tab` switcher.
- The overview's panels have the continuous corners of macOS, keys show as light capsules, and the shortcuts sheet has semibold headings.
- The `⌥Tab` switcher's highlight follows the panel's rounded corners, and its arrows to more windows are drawn chevrons.

### Fixes

- Tidy windows from the menu bar, and other actions outside the overview, now show their message on screen. Before, it only showed in the overview.
- Messages say "1 window", not "1 windows".
- Messages and search results show the keys that work there: `⌘1` to `⌘9` for search results and `⌘⇧Z` to redo in the overview.
- Leaving macOS full screen, like a full screen video, no longer flashes two desktops side by side. mielwm leaves a full screen window alone and keeps its tile for when it comes back.

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
