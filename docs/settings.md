# Settings and the menu bar

Everything you can change in the Settings window, and what the menu bar item does.

Open Settings from the menu bar item, with `⌘,` in the overview, or with `mielwm settings` from a terminal. It opens at the pane you used last.

The sidebar lists the panes in groups. The search field at its top finds a pane by its name or by a setting in it: type "gap" and Layout shows, with "Gaps" under it.

![The Layout pane](images/settings-layout-dark.png)

## General

- Open mielwm at login.
- Whether windows come back to their places after a restart.
- Animation on or off, and its speed.

## Layout

- The layout new windows get, tiles, stack or floating, and which way tiles split. Each choice is a small picture you click.
- The gaps between windows and around the screen edge, with a small desktop that redraws as you type. Point at a gap's field and its gap lights up, with its size. It shows the top gap on the display the Settings window is on.
- The top edge: Automatic, Same as other edges, or Custom. [Workspaces and layouts](workspaces.md#a-status-bar-at-the-top) explains each.
- Peek edges for stacks, so the windows behind the front one show their edges.
- Workspace key goes back: the key of the workspace you're on takes you to the one before.
- Focus and move past the edge: `⌥` arrows and `⌥⇧` arrows go on into the next workspace instead of stopping at the edge.

[Workspaces and layouts](workspaces.md) explains what each of these does.

## Windows

- Apps whose windows always float.
- Workspace rules, which send an app's windows to a fixed workspace.

## Overview

- How far the overview zooms out when it opens.
- Window names and the minimap.
- The lens, its strength and magnification.

## Keyboard

Every shortcut, grouped by what it does. Click a shortcut, then type the new keys. The search field at the top finds a shortcut by name. [Keyboard](keyboard.md) covers recording, families of keys and conflicts.

## Trackpad & mouse

- Three-finger swipes between workspaces, with a warning when macOS's own swipe gets in the way.
- The keys you hold to move a window by dragging it, or resize it with the right button: ⌃⌥ by default.
- Whether clicks, drags and scrolling work in the overview, and how fast it pans and zooms.

## Appearance

Appearance starts with a live preview of the overview, drawn by the same renderer, so every change shows as you make it.

- The accent color. Automatic follows System Settings, or pick a preset or any color.
- The glass style of every panel mielwm draws: the search field and its results, the pills and tags, the shortcuts sheet, the minimap, the `⌥Tab` switcher and the notices over the desktop. Liquid glass is clear and bends the edges of what is behind it, like macOS 26. Frosted blurs it, like earlier macOS versions. Liquid glass needs macOS 26 and is the default there. With Reduce Transparency on, every panel is solid.
- The background: your desktop picture, how much it dims, and blur.
- The grid on the canvas, dots or lines, and how strong it is.
- How windows look in the overview: corner rounding and shadows.

![The Appearance pane](images/settings-appearance-dark.png)

## Menu bar

What the mielwm item in the menu bar shows: all workspaces, the current one only, or the icon. [The menu bar](#the-menu-bar) below explains each.

Show workspace on switch puts the same numbers at the bottom of the display for a moment each time you switch, which helps when the menu bar is on another display.

## AeroSpace & Barik

- Work with Barik, so Barik's menu bar shows your workspaces. [AeroSpace and Barik](aerospace.md#barik) explains it.
- Import from AeroSpace, which reads your AeroSpace config and shows what it will apply.

## Advanced

- Show the configuration file in Finder, or open it in your editor. Any errors in it are listed here.
- Install the `mielwm` command into `~/.local/bin`. See [Command line](command-line.md).
- Reset everything. The configuration file goes to the Trash, so you can get it back.

## About

The version you run, and links to the website, these docs, the changelog, the source code and the license. About mielwm in the menu bar item's menu opens it too.

## How settings are saved

Every setting lives in `~/.config/mielwm/config.json`. Settings writes it a moment after you stop changing something, so dragging a slider is one write, not a hundred. It leaves keys it didn't touch alone, but JSON comments get lost. A setting changed back to its default disappears from the file.

Changes apply to your windows right away. Edits you make to the file yourself show up in the open Settings window as soon as you save. [Configuration file](configuration.md) lists every key.

## The menu bar

What the menu bar item shows is up to you, in Settings > Menu bar:

- All workspaces: the numbers of the workspaces that have windows, with the current one filled.
- Current only: just the current workspace's number, for a crowded menu bar or one cut short by the notch.
- Icon: the mielwm icon. Turning on Work with Barik switches All workspaces to this, since Barik shows the numbers already.

While the configuration file has errors, a warning sign takes its place.

The menu tells you what mielwm is doing: the current workspace and its layout, that it's paused, or what it's waiting for, such as a permission or AeroSpace quitting. Below that, each workspace with windows has a line with the icons of its apps, up to four, and a check on the current one. Click one to go there. From the menu you can also open the overview, tidy your windows, pause mielwm, open Settings or quit.

When an app turns on secure input, the menu says "Secure input is on, shortcuts may not work". macOS hides your keys from other apps while it's on, and mielwm's shortcuts stop until it's off. Password fields turn it on for a moment, and Terminal's Secure Keyboard Entry keeps it on until you turn it off in the Terminal menu.

Pausing puts every window back on a screen and leaves them alone until you resume. It's handy when an app misbehaves under tiling and you want normal macOS for a minute. Quitting puts the windows back too.
