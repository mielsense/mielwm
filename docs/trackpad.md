# Trackpad and mouse

Swipe between workspaces with three fingers, and use the pointer to move windows and the canvas.

## Swipe between workspaces

Three fingers left go to the next workspace, three fingers right to the previous one, the same directions as Spaces. Each swipe moves one workspace, and a Force Touch trackpad gives a click you can feel when it does. At the first or last workspace nothing happens, and there's no click.

Turn it on or off in Settings > Trackpad & mouse. It's on by default.

### macOS's own three-finger swipe

macOS swipes between full-screen apps with three fingers too. With both on, the screen does a small bounce as you swipe. Set macOS's gesture to four fingers under System Settings > Trackpad > More Gestures > Swipe between full-screen applications. Settings > Trackpad & mouse shows a warning with a button that opens that page whenever the two overlap.

Three-finger drag, an Accessibility setting, also uses three fingers. With both on, swipes and drags get in each other's way, so pick one.

### Does it slow anything down?

No. To count your fingers, mielwm looks at each trackpad touch on its way to the app under the pointer, which takes a few microseconds. It doesn't hold touches back or record them. SwipeAeroSpace works the same way. Turning swipes off removes the hook completely.

## In the overview

| Gesture | What it does |
| --- | --- |
| Two-finger scroll | Pan the canvas, under your fingers. |
| Pinch | Zoom around the pointer. |
| `⌘` or `⌃` + scroll | Zoom, for mice and trackpads alike. |
| Click | Go to a window. |
| Drag a window | Move it, also onto another workspace. |
| Drag the empty canvas | Pan, with momentum. |
| Hover | Select the window and show its name. |

"Use the pointer in the overview" in Settings > Trackpad & mouse turns all of this off, if you'd rather drive the overview by keyboard only.

## Anywhere

| Gesture | What it does |
| --- | --- |
| `⌃⌥` + left drag | Move the window under the pointer. |
| `⌃⌥` + right drag | Resize it, from the nearest corner. |
| `⌃⌥` + scroll | Zoom the canvas. Zooming out at 100% opens the overview there. |
| Middle drag | Pan the canvas. A middle click without a drag still clicks. |

Settings > Trackpad & mouse > Move and resize windows picks other keys than `⌃⌥`, such as `⌃⌘`.

Holding `⌃` alone and scrolling is left to macOS, which uses it for Accessibility Zoom.
