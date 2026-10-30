# 0002. Park windows in a corner

Accepted. Recorded October 2026.

## Context

Only one workspace shows at a time, so mielwm needs somewhere to put the windows of every other workspace. macOS has no way to hide one window and leave the rest of its app alone. Minimizing animates every window into the Dock. Hiding an app hides all of its windows, on every workspace. And macOS won't let an app move a window fully off every screen.

AeroSpace solved the same problem by moving hidden windows to a corner of a display, with a sliver left on screen.

## Decision

A window that is off camera is parked. mielwm moves it to a bottom corner of a display's visible frame with 1 point still showing, the corner that doesn't touch another display. `parkCorner` and `parkSlot` in [Placement.swift](../Sources/MielCore/Placement.swift) pick the corner the way AeroSpace does. A window with 3 points or less showing on every screen counts as hidden, whether mielwm or AeroSpace put it there.

## Consequences

- Parked windows stay ordinary windows. Apps keep running them, and ScreenCaptureKit can still take their pictures for the overview.
- A workspace switch is a batch of frame changes, with no animation from macOS to wait for.
- If mielwm stops without bringing them back, windows stay in the corner. So mielwm unparks everything when it quits, pauses or the user logs out. A small watcher process, `mielwm --watch`, unparks from the saved layout if mielwm crashes, and `mielwm --unpark` does it by hand. [Troubleshooting](../docs/troubleshooting.md) tells users about both.
- An app can pull a parked window back onto the screen. Core parks it again twice in a row, then waits 1, 2, 4, 8 and 16 seconds between tries, then leaves it until the camera moves, rather than fight the app in a loop.
