# Getting started

Install mielwm, give it the two permissions it needs, and have your windows tiled in a couple of minutes.

## Requirements

mielwm runs on macOS 15 or later, on Apple silicon. It works best with a single Space and with "Displays have separate Spaces" turned off. [Before you start](#before-you-start) explains both.

## Install

Download `mielwm.dmg` from the [latest release](https://github.com/mielsense/mielwm/releases/latest), open it and drag mielwm into Applications. Open it from Applications, not from the disk image.

mielwm is signed but not notarized by Apple, so the first time you open it macOS says it can't check the developer. Click Done, then go to System Settings > Privacy & Security, scroll down and click Open Anyway. You only do this once.

## Permissions

mielwm asks for two permissions, both under System Settings > Privacy & Security. The first launch lists them, with a button that opens the right page for each.

![The first launch, asking for permissions](images/onboarding-dark.png)

**Accessibility** lets mielwm move and focus windows and hear its shortcuts. It can't do anything without it.

**Screen Recording** gives it the live window pictures in the [overview](overview.md). Without it everything else still works, and the overview shows plain cards instead of pictures. macOS applies this permission only after mielwm restarts, and asks you to confirm it again every so often.

The pictures stay in memory while mielwm runs. mielwm doesn't save them to disk, and it has no network code, so nothing about your screen leaves your Mac.

## Before you start

**Quit any other window manager.** Two of them moving the same windows fight each other. If AeroSpace is running, mielwm offers to quit it and waits until it's gone. Set `start-at-login = false` in `~/.config/aerospace/aerospace.toml` so it doesn't come back at login. [AeroSpace and Barik](aerospace.md) covers moving your setup over.

**Turn off "Displays have separate Spaces"** under System Settings > Desktop & Dock > Mission Control, then log out and back in. With it on, a window can't sit across two displays. mielwm reminds you once.

**Use one Space.** mielwm's workspaces replace Spaces. It doesn't manage other Spaces or apps in native fullscreen.

## First steps

Every window you had open lands on its own workspace, numbered from 1. Try these:

- `⌥1` to `⌥9` go to a workspace.
- `⌥⇧2` moves the focused window to workspace 2 and follows it there.
- `⌥/` tiles windows side by side, `⌥,` stacks them, `⌥.` floats one.
- `⌃⌥G` zooms out to see everything. Type to search, `Return` to go.
- Three fingers left or right on the trackpad switch workspaces.

If you used AeroSpace, the keys already match. [Keyboard](keyboard.md) has the full list, and Settings lets you change any of them.

## Updating

Download the new `mielwm.dmg`, quit mielwm from its menu bar item, and drag the new copy into Applications to replace the old one. Your settings and window layout stay where they are. Every release is signed with the same identity, so macOS keeps your permissions too.

The [changelog](https://github.com/mielsense/mielwm/blob/main/CHANGELOG.md) lists what changed in each version.

## Uninstalling

1. If Work with Barik is on, turn it off in Settings first. That puts Barik's config back the way it was.
2. Quit mielwm from its menu bar item. Every window goes back on a screen.
3. Drag mielwm from Applications to the Trash.
4. To remove your settings too, delete `~/.config/mielwm` and `~/Library/Application Support/mielwm`.

If you installed the command-line tool, also delete `~/.local/bin/mielwm`. You can remove mielwm from the Accessibility and Screen Recording lists in System Settings, though macOS doesn't mind if you leave it there.

## Building it yourself

You need the Command Line Tools, which `xcode-select --install` sets up. Xcode isn't required.

```sh
git clone https://github.com/mielsense/mielwm.git
cd mielwm
scripts/build-app.sh --install
open ~/Applications/mielwm.app
```

`--install` copies the app to `~/Applications`, quitting a running copy first so its windows go back on screen. The script signs your build with an identity it creates once, so your permissions survive rebuilds. [CONTRIBUTING.md](https://github.com/mielsense/mielwm/blob/main/CONTRIBUTING.md) has the details.
