# Troubleshooting

What to check when something doesn't behave.

## Windows are stuck in a screen corner

Windows outside the camera wait in a bottom corner, and mielwm puts them all back on a screen when it quits, pauses, gets `Ctrl-C` or `kill`, or you log out. If mielwm crashes, a small watcher process puts them back from the saved layout. If even that didn't happen, run:

```sh
mielwm --unpark
```

## Shortcuts do nothing

Check that mielwm is turned on under System Settings > Privacy & Security > Accessibility. If you build mielwm yourself and the build fell back to an ad hoc signature, macOS treats every build as a new app: remove mielwm from the list and add it again.

Another app may own the same keys. Settings > Keyboard tells you when macOS uses a shortcut, and you can change any of mielwm's there.

## The overview shows blank cards

Screen Recording is missing, or was granted while mielwm was running. macOS applies that permission only after a restart, so quit mielwm and open it again.

## Windows jump back after you move them

Something else is moving them too, like AeroSpace, Rectangle, or an app with its own window handling. Quit it. A tiled window also snaps back if you drag it smaller than its tile, which is on purpose: drag the edge between two tiles instead, or float it with `⌥.`.

## A window isn't managed at all

Some windows can't be moved or resized, such as certain dialogs and fixed panels, and mielwm leaves them alone. `mielwm --list-windows` shows what mielwm sees and can move.

## Swipes bounce the screen

macOS's own three-finger swipe between full-screen apps is still on. Set it to four fingers under System Settings > Trackpad > More Gestures. [Trackpad and mouse](trackpad.md) has the details.

## A window can't sit across two displays

"Displays have separate Spaces" is on. Turn it off under System Settings > Desktop & Dock > Mission Control, then log out and back in.

## The configuration has errors

The menu bar item turns into a warning sign, and the menu and Settings > Advanced list each error. If the file isn't valid JSON, mielwm uses its defaults until you fix it. [Configuration file](configuration.md) lists every key.

## Reporting a bug

[Open an issue](https://github.com/mielsense/mielwm/issues/new/choose) with your macOS version, what you did and what happened. `mielwm state` and `mielwm --list-windows --json` show mielwm's view of your windows, which helps.
