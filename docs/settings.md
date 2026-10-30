# Settings and the menu bar

Everything you can change in the Settings window, and what the menu bar item does.

Open Settings from the menu bar item, with `⌘,` in the overview, or with `mielwm settings` from a terminal. It opens at the pane you used last.

![The Layout & workspaces pane](images/settings-layout-dark.png)

## General

- Open mielwm at login.
- What the menu bar item shows: all workspaces, the current one only, or the icon.
- How far the overview zooms out when it opens.
- Whether clicks, drags and scrolling work in the overview.
- Animation on or off, and its speed.
- Whether windows come back to their places after a restart.

## Layout & workspaces

- The layout new windows get, tiles, stack or floating, and which way tiles split.
- The gaps between windows and around the screen edge, with a small diagram that updates as you type. It shows the top gap on the display the Settings window is on.
- The top edge: Automatic, Same as other edges, or Custom. [Workspaces and layouts](workspaces.md#a-status-bar-at-the-top) explains each.
- Three-finger swipes between workspaces, with a warning when macOS's own swipe gets in the way.
- Workspace rules, which send an app's windows to a fixed workspace.
- Apps whose windows always float.
- Work with Barik, so Barik's menu bar shows your workspaces. [AeroSpace and Barik](aerospace.md#barik) explains it.
- Import from AeroSpace, which reads your AeroSpace config and shows what it will apply.

[Workspaces and layouts](workspaces.md) explains what each of these does.

## Keyboard

Every shortcut, grouped by what it does, with a recorder for each. [Keyboard](keyboard.md) covers recording, families of keys and conflicts.

## Appearance

Appearance starts with a live preview of the overview, drawn by the same renderer, so every change shows as you make it.

- The accent color. Automatic follows System Settings, or pick a preset or any color.
- The lens, its strength and magnification.
- The background: your desktop picture, how much it dims, and blur.
- The grid on the canvas, dots or lines, and how strong it is.
- How windows look in the overview: corner rounding, shadows, names and the minimap.

![The Appearance pane](images/settings-appearance-dark.png)

## Advanced

- Show the configuration file in Finder, or open it in your editor. Any errors in it are listed here.
- Install the `mielwm` command into `~/.local/bin`. See [Command line](command-line.md).
- Reset everything. The configuration file goes to the Trash, so you can get it back.

## How settings are saved

Every setting lives in `~/.config/mielwm/config.json`. Settings writes it a moment after you stop changing something, so dragging a slider is one write, not a hundred. It leaves keys it didn't touch alone, but JSON comments get lost. A setting changed back to its default disappears from the file.

Changes apply to your windows right away. Edits you make to the file yourself show up in the open Settings window as soon as you save. [Configuration file](configuration.md) lists every key.

## The menu bar

What the menu bar item shows is up to you, in General > Menu bar:

- All workspaces: the numbers of the workspaces that have windows, with the current one filled.
- Current only: just the current workspace's number, for a crowded menu bar or one cut short by the notch.
- Icon: the mielwm icon. Turning on Work with Barik switches to this, since Barik shows the numbers already.

While the configuration file has errors, a warning sign takes its place.

The menu tells you what mielwm is doing: the current workspace and its layout, that it's paused, or what it's waiting for, such as a permission or AeroSpace quitting. Below that, each workspace with windows has a line with the icons of its apps, up to four, and a check on the current one. Click one to go there. From the menu you can also open the overview, tidy your windows, pause mielwm, open Settings or quit.

When an app turns on secure input, the menu says "Secure input is on, shortcuts may not work". macOS hides your keys from other apps while it's on, and mielwm's shortcuts stop until it's off. Password fields turn it on for a moment, and Terminal's Secure Keyboard Entry keeps it on until you turn it off in the Terminal menu.

Pausing puts every window back on a screen and leaves them alone until you resume. It's handy when an app misbehaves under tiling and you want normal macOS for a minute. Quitting puts the windows back too.
