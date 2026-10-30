# Troubleshooting

What to check when something doesn't behave.

## Shortcuts do nothing

First check that mielwm is turned on under System Settings > Privacy & Security > Accessibility. If it's on and the shortcuts still do nothing, remove mielwm from the list with the minus button, add it back, and open mielwm again.

Another app may own the same keys. Settings > Keyboard warns when macOS uses a shortcut, and you can move any of mielwm's to other keys there.

## The overview shows blank cards

Screen Recording is missing, or you granted it while mielwm was running. macOS applies that permission only after a restart, so quit mielwm and open it again.

## Windows are stuck in a screen corner

Windows you aren't looking at wait in a bottom corner of a display, and mielwm brings them all back when it quits, pauses, or you log out. If mielwm crashes, or an app doesn't answer while mielwm quits, a small watcher brings them back from the saved layout. If windows are still stuck after that, run:

```sh
mielwm --unpark
```

## Windows are out of place

mielwm puts windows back on its own after the Mac wakes from sleep or a display comes or goes. If windows still don't sit where they should, run `mielwm refresh`. It reads every app's window list again and puts every window back where the canvas says.

## Windows jump back after you move them

Something else is moving them too, like AeroSpace, Rectangle, or an app with its own window handling. Quit it.

A tiled window also snaps back when you drag it smaller than its tile. That's on purpose. Drag the edge between two tiles instead, or float the window with `⌥.`.

## An app behaves badly when tiled

Some apps don't like being resized by someone else, and flicker or ignore the size. Float that window with `⌥.`, or add the app under Settings > Windows > Floating apps so all its windows float.

## A window isn't managed at all

Some windows can't be moved or resized, such as certain dialogs and fixed-size panels, and mielwm leaves them alone. `mielwm --list-windows` lists the windows mielwm sees and can move.

## AeroSpace keeps coming back

mielwm stops while AeroSpace runs, and offers to quit it. If AeroSpace starts again at login, set `start-at-login = false` in `~/.config/aerospace/aerospace.toml`.

## Swipes bounce the screen

macOS's own three-finger swipe between full-screen apps is still on. Set it to four fingers under System Settings > Trackpad > More Gestures. [Trackpad and mouse](trackpad.md) has the details.

## A window can't sit across two displays

"Displays have separate Spaces" is on. Turn it off under System Settings > Desktop & Dock > Mission Control, then log out and back in.

## Barik doesn't show mielwm's workspaces

- Check that Work with Barik is on in Settings > AeroSpace & Barik.
- If the switch asked you to open Barik first, Barik had no config file yet. Open Barik once, quit it, and turn the switch on again.
- If you moved mielwm.app, quit and reopen mielwm. It points Barik at the new place when it starts.

[AeroSpace and Barik](aerospace.md#barik) explains what the switch changes.

## The configuration has errors

The menu bar item turns into a warning sign, and the menu and Settings > Advanced list each error. If the file isn't valid JSON, mielwm uses its defaults until you fix it. A single bad value is skipped and the rest still apply. [Configuration file](configuration.md) lists every key.

## You built mielwm yourself and macOS keeps asking for permissions

Your build fell back to an ad hoc signature, so macOS sees every build as a new app. `scripts/build-app.sh` says so when it happens. Check the message it printed, fix the signing, then remove mielwm from both permission lists and add it again.

## Reporting a bug

[Open an issue](https://github.com/mielsense/mielwm/issues/new/choose) with your macOS version, what you did and what happened. The output of `mielwm state` and `mielwm --list-windows --json` shows how mielwm saw your windows, which often explains the problem.
