# Changelog

What changed in the mielwm app, newest version first. Versions follow [semantic versioning](https://semver.org). While mielwm is below 1.0, a new minor version can change how things work.

## Unreleased

Nothing yet.

## 0.1.1

Released October 30, 2026.

### On screen

- Switching workspaces shows the workspace numbers at the bottom of the display for a moment, with the current one filled. Turn it off in Settings > Menu bar.
- Going to a stack, or bringing another of its windows to the front, shows a strip at the top with each window's icon and title and where you are, like "2 of 4".
- Stacks can show the edges of the windows behind the front one. Set Peek edges in Settings > Layout.
- The overview's search field, results, shortcuts sheet, key hints, toasts and the `⌥Tab` switcher are drawn by macOS itself. On macOS 26 they're Apple's own Liquid glass and bend the canvas behind them.
- Settings > Appearance > Glass style picks Liquid glass, the default on macOS 26, or Frosted, the blur of earlier versions, for every panel and notice.
- The overview's search field is a capsule, like Spotlight, with the results in their own card just below it.
- The overview's panels have the continuous corners of macOS, and keys show as light capsules.
- Tidy windows from the menu bar, and other actions outside the overview, show their message on screen. Before, it only showed in the overview.
- VoiceOver says the workspace you switch to, the app selected in the `⌥Tab` switcher, messages like "Tidied 4 windows", and in the overview the selected window, its app and its place among the search results.

### Workspaces and layouts

- `⌥` arrows and `⌥⇧` arrows stop at the edge of the workspace, as in AeroSpace. Turn on Settings > Layout > Focus and move past the edge to keep going into the next one.
- A new `workspace-back-and-forth` action goes to the workspace you were on before. It has no key by default, since `⌥Tab` is the window switcher. Turn on Settings > Layout > Workspace key goes back, and the key of the workspace you're on does the same.
- Window rules can match an app's name or a window's title, so a Picture-in-Picture or splash window can float or open on a fixed workspace. They live in the config file.
- `resize` takes an amount and a side, like AeroSpace's `resize smart +100` or `resize width -50`.
- Close and minimize the focused window from a shortcut or the command line. Neither has a key by default.
- Import from AeroSpace also brings over rules by app name or title, `workspace-back-and-forth`, `close`, `macos-native-minimize`, `resize` with any amount, and `--auto-back-and-forth`. `⌥Tab` stays the window switcher.
- The top gap leaves room for a status bar only on displays that have one. Without one, external displays get the same 12 point top gap as the built-in display instead of 54. Settings > Layout > Top edge also offers Same as other edges and Custom, and a number already in your config keeps working as Custom.

### Settings and the menu bar

- The Settings window looks and reads like System Settings: a search field in the sidebar that finds panes and settings, a header on each pane, and pictures to click for the layout, the orientation, the grid style and the menu bar item.
- Settings has new panes, so each setting is where you'd look for it: Windows, Overview, Trackpad & mouse, Menu bar, AeroSpace and About. Every setting keeps its name in the config file.
- The gaps diagram is a small desktop that redraws as you type. Pointing at a gap's field lights up that gap with its size.
- Shortcuts show as light key caps, and a search field in Settings > Keyboard finds one by name.
- Settings > Trackpad & mouse sets the keys you hold to move and resize windows, and how fast the overview pans and zooms. These were in the config file only.
- On macOS 26 and later, mielwm's windows use the system's current look, with the new sidebar, grouped rows and controls.
- Settings > AeroSpace > Work with AeroSpace-compatible apps lets status bars built for AeroSpace, like Barik, show mielwm's workspaces. It works with any of them, and edits Barik's config only when there is one.
- The menu bar item can show all workspaces, the current one only, or the icon. Turning on Work with AeroSpace-compatible apps switches All workspaces to the icon.
- The menu lists each workspace with windows, with its apps' icons and a check on the current one. Click one to go there.
- The menu warns when secure input is on, since mielwm's shortcuts don't work while it is.
- About mielwm in the menu opens Settings > About, with the version and links to the website, docs, changelog and source.
- The welcome window lists its two permissions the way Privacy & Security does, with a badge on each one you allowed.

### Windows stay where they belong

- Closing, minimizing or hiding the focused window keeps you on the same workspace. The most recent window on screen takes focus.
- An app that resizes its own window, like an Electron app restoring its size, no longer shifts the split between tiles. Only dragging an edge does.
- A tiled window you drag away goes back to its tile when you let go, every time.
- A window from another workspace that its app keeps putting back on screen is tucked away again after a short wait.
- A window whose app refuses its tile size settles at the size it wants, instead of being resized again each time the app reports a move.
- With displays of different widths, a display never shows part of the workspace next to it.
- Switching workspaces no longer flashes the old windows over the new ones, and no longer leaves windows behind when their apps are slow to answer. A move an app misses gets sent once more.
- mielwm reads every app's window list again every 10 seconds and when you switch to an app. A window that opened while its app was busy gets picked up, and a closed window no longer leaves an empty tile.
- Apps that start slowly or turn into regular apps later get their windows managed. Windows that open as a dialog and become normal windows later get tiled.
- Apps already hidden when mielwm starts no longer hold empty tiles.
- After the Mac wakes from sleep, windows go back to their tiles on their own.
- After a restart, windows find their places even when their title changed, like a browser tab.
- Leaving macOS full screen, like a full screen video, no longer flashes two desktops side by side.
- Quitting while an app is busy no longer leaves its windows in a screen corner. The watcher brings them back after mielwm exits.

### Fixes

- After you click the desktop, a dialog or an app mielwm leaves alone, window keys like `⌥T` no longer act on the last window you used.
- After Esc closes the overview, the window you were on keeps the keyboard.
- Closing the welcome window no longer leaves the menu stuck on Waiting for permissions. Without Accessibility, mielwm stays paused, and Resume mielwm opens the window again.
- If Restart mielwm in the welcome window can't start the new copy, mielwm stays open instead of quitting.
- The menu keeps warning that shortcuts need the Accessibility permission after the config file changes.
- Settings > Windows shows and keeps a workspace rule for a workspace past 9, like `com.x=12`.
- A display plugged in, removed or rearranged while mielwm starts is picked up at once.
- Pausing or quitting mielwm while you type or click can no longer crash it.
- Key caps look the same everywhere. The ones in desktop toasts were too faint on glass.
- Counts read "1 window" and "1 floating app", not "1 windows". Text uses straight quotes and plain hyphens, like `⌘1-9`.
- Messages and search results show the keys that work there: `⌘1` to `⌘9` for search results and `⌘⇧Z` to redo in the overview.
- `mielwm refresh` also reads every app's window list again.

### Performance

- mielwm uses about 40 MB less memory at rest. It keeps the desktop picture once instead of twice.
- The overview uses about half the CPU while your windows sit still, and switching workspaces uses less too.
- The `aerospace` command that status bars run many times a second uses about a third less CPU per call.
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
