# Workspaces

Numbered workspaces hold your windows, side by side on one canvas, and you switch between them with a key or a swipe.

## The canvas

Every window has a place on the canvas, a surface much larger than your screens. Normally you look at one screen-sized part of it, and mielwm puts the real windows wherever the canvas says.

Windows outside that part wait in a bottom corner of a display, with one point still on screen. AeroSpace hides windows the same way, because macOS doesn't let an app truly hide another app's window. They stay ordinary macOS windows the whole time, and mielwm puts them all back on screen when it quits or pauses.

## Workspaces 1 to 9

A workspace is a screen-sized area of the canvas. Workspaces 1 to 9 sit side by side in a fixed row, so `⌥3` always lands in the same place. A workspace with no windows disappears once you leave it, and its number is free again.

Each workspace has its own [layout](layouts.md): tiles, a stack, or floating windows.

## Switching

| Keys | What it does |
| --- | --- |
| `⌥1` … `⌥9` | Go to that workspace. |
| `⌥⇧1` … `⌥⇧9` | Move the focused window to that workspace and go with it. |
| `⌃←`, `⌃→` | The previous or next workspace that has windows. They stop at the first and last. |
| Three fingers left or right | The same, from the trackpad. See [Trackpad and mouse](trackpad.md). |

Switching is instant, with no animation. The workspace numbers show at the bottom of the display for 0.7 seconds, with the current one filled, and the menu bar item shows them too. [Menu bar and indicators](menu-bar.md) explains both.

### Going back

The Last workspace action goes to the workspace you were on before, and again goes back. It has no key until you give it one in Settings > Keyboard, because `⌥Tab` is the window switcher.

Turn on Settings > Layout > Workspace key goes back, and the key of the workspace you're on does the same: on workspace 3, `⌥3` takes you back to where you came from. `mielwm workspace 3` from the [command line](command-line.md) and clicks in a menu bar app stay put.

## New windows

A new window joins the workspace you're on, next to the focused window, and takes that workspace's layout. A new workspace starts with the layout from Settings > Layout > New windows, which is tiles unless you change it.

Some windows go elsewhere:

- Apps in Settings > Windows > Floating apps always float.
- Apps in Settings > Windows > Workspace rules open on their own workspace, so Spotify can always open on 2.
- [Window rules](window-rules.md) in the config file float a window or send it to a workspace by its app's name or its title.
- Windows that can't be resized float.

When mielwm starts, every window that's already open gets a workspace of its own, unless a rule says otherwise. That way nothing starts as a pile of tiny tiles.

## Closing and minimizing

Closing, minimizing or hiding the focused window keeps you on the same workspace. The most recent window on screen takes the focus. Close and Minimize are also actions you can give a key in Settings > Keyboard.

## More than one display

The workspace you go to lands on the display under the pointer. The other displays keep showing whatever part of the canvas sits there. Workspaces sit far enough apart that a wide display never shows part of the workspace next to it.

## Keeping track of windows

mielwm hears about new, moved and closed windows from macOS. Apps that are busy sometimes miss a move or a notification, so mielwm also:

- reads every app's window list again every 10 seconds, and when you switch to an app,
- gives a window that missed a move the same move once more a second later,
- puts every window back in its tile after the Mac wakes from sleep or a display comes or goes.

Nothing is read while the displays sleep. If windows still end up out of place, `mielwm refresh` reads every list again and puts every window where the canvas says.
