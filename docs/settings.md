# Settings and the menu bar

Everything you can change from the Settings window, and what the menu bar item does.

Open Settings from the menu bar item (Settings…), with `⌘,` in the overview, or with `mielwm settings` from a terminal. It opens at the pane you used last.

![The Layout & workspaces pane](images/settings-layout-dark.png)

## General

Open at login, the workspace numbers in the menu bar, how far the overview zooms out, whether the pointer works in the overview, animation and its speed, and whether windows come back to their places after a restart.

## Layout & workspaces

The layout new windows get (tiles, stack or floating) and the orientation of tiles, the gaps, with a small diagram that updates as you type, three-finger swipes, workspace rules (an app always opens on a given workspace), floating apps, Barik support and Import from AeroSpace. [Workspaces and layouts](workspaces.md) explains what each of these does.

## Keyboard

Every shortcut, grouped, with a recorder for each. [Keyboard](keyboard.md) covers how recording, families of keys and conflicts work.

## Appearance

Appearance starts with a live preview of the overview, drawn by the real renderer, so you see each change as you make it. Then come the accent color (Automatic follows System Settings, or pick a preset or any color), the lens (on or off, strength, magnification), the background (desktop picture, dimming, blur), the grid (style, opacity) and how windows look (corner rounding, shadows, names, the minimap).

![The Appearance pane](images/settings-appearance-dark.png)

## Advanced

Show or open the configuration file, install the `mielwm` command-line tool into `~/.local/bin`, and reset everything (the file goes to the Trash, so you can get it back). If the file has errors, they're listed here.

## How settings are saved

Settings writes `~/.config/mielwm/config.json` a moment after you stop changing something, so dragging a slider is one write. It leaves every key it didn't touch alone, though JSON comments get lost. A value set back to its default leaves the file. Changes reach the canvas right away, and edits you make to the file yourself show up in the open window as soon as you save. [Configuration file](configuration.md) lists every key.

## The menu bar

The menu bar item shows the numbers of the workspaces that have windows, with the current one filled. Turn that off in General and it shows the mielwm icon instead. A warning sign takes its place while the configuration has errors.

The menu says what mielwm is doing: the current workspace and its layout, paused, or what it's waiting for (permissions, or AeroSpace to quit). It also has the overview, Tidy windows, Pause mielwm, Settings, About and Quit.

Paused, mielwm puts every window back on a screen and leaves them alone until you resume. Quitting does the same.
