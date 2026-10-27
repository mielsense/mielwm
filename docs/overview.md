# The overview

Zoom out to see every window at once as a live picture, then search or point to go anywhere.

![The overview with search](images/search-dark.jpg)

## Opening it

`⌃⌥G` zooms out, and `⌃⌥G` again comes back. The view pulls back through a curved lens so the edges of the canvas bend away, and the workspace you were on sits in the middle with room to spare. `Esc` goes back to exactly where you started. You can rebind the key in Settings > Keyboard (plenty of people use `⌥Space`).

## Search

Start typing as soon as it opens. mielwm searches window titles and app names. Every word you type has to appear, with its letters together, so `fas` finds `fastfetch` and `term git` finds a Terminal window titled with git. Case and accents don't matter, and dead keys and input methods work.

| Keys | What it does |
| --- | --- |
| `↑` `↓`, `Tab` `⇧Tab` | Move through the results. With no search, `Tab` walks your recent windows. |
| `⌘1` … `⌘9` | Go straight to that result. |
| `Return` | Go to the selected window. |
| `⇧Return` | Bring the selected window to where you are. |
| `⌘⌫` | Clear the search. |
| `Esc` | Clear the search, then go back. |

## Moving around

| Keys | What it does |
| --- | --- |
| Arrows | Select the nearest window that way. |
| `⇧` arrows | Nudge the selected window. |
| `⌘` arrows | Pan. |
| `⌘=`, `⌘-` | Zoom in, out. |
| `⌘0` | Fit every window, or every match while searching. |
| `⌘F` | Frame the selected window. |
| `⌘A` | Tidy every floating window onto the grid, grouped by app. |
| `⌘Z`, `⌘⇧Z` | Undo, redo moves and tidying. |
| `⌘,` | Open Settings at Appearance. |
| `⌘/` | Show every key. |

The `⌃` versions of these keys (`⌃0`, `⌃Z` and so on) and `F1` work too.

With a trackpad or mouse, click a window to go to it and drag one to move it, including onto another workspace. Scroll with two fingers or drag the empty canvas to pan, and pinch or `⌘`-scroll to zoom. Hovering a window selects it and shows its name. If you'd rather keep the pointer out of it, turn off "Use the pointer" in Settings > General.

## The minimap

The minimap in the corner shows the whole canvas, your workspaces and the part you're looking at. Click it to jump, and use the button next to it to tidy up. Settings > Appearance turns it off.

## The lens

The bend at the edges is the lens. Settings > Appearance turns it off, and sets its strength and how far the canvas extends under it. The lens follows Reduce Motion: with it on, mielwm cuts instead of flying.

## How the pictures work

The overview draws live pictures of your windows with ScreenCaptureKit and Metal. Windows that are still cost almost nothing to show, and windows playing video update up to 60 times a second. When the overview closes, the live pictures turn into small stills and the memory goes back. [Performance](performance.md) has the numbers.
