# The overview

Zoom out to see every window at once as a live picture, then search or point to go anywhere.

![The overview with search](images/search-dark.jpg)

## Opening it

`⌃⌥G` zooms out, and `⌃⌥G` again comes back. The view pulls back through a curved lens so the edges of the canvas bend away, and the workspace you were on sits in the middle with room to spare. `Esc` goes back to exactly where you started.

`⌃⌥G` stays clear of AeroSpace's keys, but it's a stretch to press. `⌥Space` is easier, if no launcher already has it. Change it in Settings > Keyboard.

## Search

Start typing as soon as it opens. mielwm searches window titles and app names, and the results narrow with each letter.

Every word you type has to appear somewhere, with its letters together. So `fas` finds `fastfetch`, and `term git` finds a Terminal window with git in its title. Case and accents don't matter, and dead keys and input methods work as usual.

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

The `⌃` versions of these keys, like `⌃0` and `⌃Z`, work too, and so does `F1` for the key list.

## With the pointer

Click a window to go to it, or drag it somewhere else, onto another workspace too. Scroll with two fingers or drag the empty canvas to pan, and pinch or `⌘`-scroll to zoom. Hovering a window selects it and shows its name.

If you'd rather drive the overview by keyboard only, turn off "Use the pointer in the overview" in Settings > Trackpad & mouse.

## The minimap

The minimap in the corner shows the whole canvas, your workspaces and the part you're looking at. Click it to jump there. The button next to it tidies your floating windows. Settings > Overview turns the minimap off.

## The lens

The bend at the edges is the lens. It's there so the windows around the edge stay in view without shrinking everything else. Settings > Overview sets its strength and how far the canvas extends under it, or turns it off.

With Reduce Motion on in System Settings > Accessibility, mielwm cuts between views instead of flying.

## Window pictures

The pictures are live while the overview is open, and need the Screen Recording permission. Without it, windows show as plain cards. A window that sits still costs almost nothing to show, and one playing video updates up to 60 times a second. [Performance](performance.md) has the numbers.
