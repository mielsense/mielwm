# Install

Download mielwm, open it once past macOS's check, and keep it up to date.

## Requirements

mielwm runs on macOS 15 or later, on Apple silicon. It works best with a single Space and with "Displays have separate Spaces" turned off. [First steps](first-steps.md#before-you-start) explains both.

## Download and open

1. Download mielwm from the [download page](https://wm.miel.my/download). It also lists the version, its size, its SHA-256 and older versions.
2. Open it and drag mielwm into Applications.
3. Open mielwm from Applications, not from the disk image.

mielwm is signed but not notarized by Apple, so the first time you open it macOS says it can't check the developer. Click Done, then go to System Settings > Privacy & Security, scroll down and click Open Anyway. You do this once.

The welcome window then asks for two permissions. [First steps](first-steps.md) walks through them.

## Updating

1. Download the new version from the [download page](https://wm.miel.my/download).
2. Quit mielwm from its menu bar item. Every window goes back on a screen.
3. Drag the new copy into Applications to replace the old one, and open it.

Your settings and window layout stay where they are. Every release is signed with the same certificate, so macOS keeps your permissions too. The [changelog](../CHANGELOG.md) lists what changed in each version.

## Uninstalling

1. If Settings > AeroSpace > Work with AeroSpace-compatible apps is on, turn it off first. That puts Barik's config back the way it was.
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

`--install` copies the app to `~/Applications`, quitting a running copy first so its windows go back on screen. The script signs your build with an identity it creates once, so your permissions survive rebuilds. [CONTRIBUTING.md](../CONTRIBUTING.md) has the details.
