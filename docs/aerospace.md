# What's different

mielwm follows AeroSpace's keys and model, adds a canvas you can zoom out of, and leaves a few AeroSpace features out.

## What stays the same

mielwm's defaults follow AeroSpace's:

- `⌥1`…`⌥9` go to a workspace, and `⌥⇧1`…`⌥⇧9` move a window there.
- `⌥/` tiles, and `⌥,` gives you what AeroSpace calls accordion and mielwm calls a [stack](stacks.md).
- `⌥` arrows focus, and `⌥⇧` arrows move. Both stop at the edge of the workspace.
- The gaps are the same 8 and 12 points.
- Windows you aren't looking at wait in a screen corner, the way AeroSpace hides them.

The model is close too. A workspace tiles its windows, a window can float, and apps can be sent to a fixed workspace.

## What mielwm adds

- Every workspace sits on one canvas you can zoom out of, in [the overview](overview.md), with live window pictures and search.
- Three-finger swipes between workspaces, with no extra app. See [Trackpad and mouse](trackpad.md).
- `⌥Tab` is a recent-windows switcher. See [Focus and switching](focus.md#recent-windows).
- `⌃⌥` and a drag moves or resizes any window from anywhere inside it.
- A workspace pill and a stack strip show where you are. See [Menu bar and indicators](menu-bar.md).
- Every setting has a place in a Settings window, and the config file is JSON.

## What works differently

- `workspace-back-and-forth` has no key by default, because `⌥Tab` is the window switcher. Bind it in Settings > Keyboard, where it's called Last workspace.
- `workspace --auto-back-and-forth` is one setting for all the workspace keys, Settings > Layout > Workspace key goes back, instead of a flag on each key.
- `resize` changes a tile only along its split, and only by an amount. `resize width 800`, which sets a size, isn't supported.
- Window rules match the app's bundle id, its name or the window's title, and can float a window or send it to a workspace. The other `on-window-detected` conditions and commands aren't there. See [Window rules](window-rules.md).
- Focus and move can cross into the next workspace if you turn on Settings > Layout > Focus and move past the edge.

## What isn't there

- There are no binding modes like AeroSpace's service mode.
- There are no nested containers. A workspace is tiles or a stack, one level deep, so `join-with` and `split` don't exist.
- `⌥⇧Tab`, which moves a workspace to another monitor in AeroSpace, has no equivalent yet. In mielwm it walks the window switcher backwards.

## Switching over

Quit AeroSpace before you start mielwm, because two window managers fight over the same windows. mielwm offers to do it and waits until AeroSpace is gone. If SwipeAeroSpace runs too, it offers to quit both. Set `start-at-login = false` in your AeroSpace config so it stays gone.

Then [import your config](import.md), and if a menu bar app shows your AeroSpace workspaces, point it at mielwm. See [AeroSpace-compatible apps](compatible-apps.md).

The real AeroSpace and its `aerospace` command stay untouched, so you can go back any time.
