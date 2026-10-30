# AeroSpace and Barik

Move your AeroSpace setup over, and keep using Barik's workspace widget with mielwm.

## Coming from AeroSpace

mielwm's defaults follow AeroSpace's. `⌥1`…`⌥9` go to a workspace, `⌥⇧1`…`⌥⇧9` move a window, `⌥/` tiles and `⌥,` gives you what AeroSpace calls accordion and mielwm calls a stack. Focus and move use the same arrows, and the gaps are the same 8 and 12 points.

The model is close too. A workspace tiles its windows, a window can float, and apps can be sent to a fixed workspace. What's new is the canvas around it. Every workspace sits on one surface you can zoom out of, in [the overview](overview.md).

A few things work differently or aren't there yet:

- `⌥Tab` is mielwm's recent-windows switcher. `workspace-back-and-forth` is there with no key, so bind it in Settings > Keyboard.
- `workspace --auto-back-and-forth` is a setting for all the workspace keys, Settings > Layout > Workspace key goes back, instead of a flag on each key.
- `⌥⇧Tab`, which moves a workspace to another monitor in AeroSpace, has no equivalent yet.
- There are no binding modes like AeroSpace's service mode, and no nested containers. A workspace is tiles or a stack, one level deep, so `join-with` and `split` don't exist.
- `resize` changes a tile only along its split, and only by an amount. `resize width 800`, which sets a size, isn't supported.
- Window rules match the app's bundle id, its name or the window's title, and can float a window or send it to a workspace. The other `on-window-detected` conditions and commands aren't there.

Quit AeroSpace before you start mielwm, because two window managers fight over the same windows. mielwm offers to do it and waits until AeroSpace is gone. Set `start-at-login = false` in your AeroSpace config so it stays gone.

## Import your AeroSpace config

Settings > AeroSpace & Barik > Import from AeroSpace reads `~/.config/aerospace/aerospace.toml`, or `~/.aerospace.toml`, shows what it found, and applies it when you confirm. It understands:

- `[gaps]`, including the per-monitor form. `monitor."built-in"` becomes the built-in display's top gap, and the plain value the other displays'.
- `default-root-container-layout`, with `accordion` becoming a stack, and `default-root-container-orientation`.
- `[[on-window-detected]]` blocks with `if.app-id`. `run = "move-node-to-workspace N"` becomes a workspace rule, and `run = "layout floating"` a floating app.
- `[[on-window-detected]]` blocks with `if.app-name-regex-substring` or `if.window-title-regex-substring` become [window rules](configuration.md#window-rules) with the same `run`. Importing again replaces the rules an earlier import added.
- `[mode.main.binding]` keys whose command mielwm has: `focus`, `move`, `workspace N|next|prev`, `workspace-back-and-forth`, `move-node-to-workspace N`, also as the first of several commands, `layout tiles|accordion|floating`, `fullscreen`, `resize smart|width|height ±N`, `close` and `macos-native-minimize`. A key using `--auto-back-and-forth` turns on `layout:auto_back_and_forth`. `alt-tab` keeps mielwm's window switcher.

The very first time mielwm starts, before any config exists, it imports the gaps, layout and rules on its own and tells you. It leaves the keys alone, since the defaults already match AeroSpace's.

## Barik

[Barik](https://github.com/mocki-toki/barik) is a menu bar replacement that shows your AeroSpace or yabai workspaces and switches to one when you click it. mielwm can feed it, with no change to Barik and no plugin to install.

### Turning it on

1. Open Barik at least once, so it writes its config file.
2. Make sure mielwm runs from your Applications folder. From the disk image or straight from Downloads, the switch asks you to move it first, because that copy disappears when mielwm quits.
3. Turn on Settings > AeroSpace & Barik > Work with Barik, and confirm.

Barik relaunches, and a few seconds later it shows mielwm's workspaces and the windows on each. Clicking a workspace or a window switches to it.

### What it changes on your Mac

Barik only looks for a running app called AeroSpace, and asks the `aerospace` command about workspaces. So mielwm gives it both:

- A tiny hidden helper app named AeroSpace runs while the switch is on. It quits by itself when mielwm quits.
- mielwm adds one line to Barik's config, `~/.barik-config.toml` or `~/.config/barik/config.toml`, pointing `aerospace.path` at a small command inside mielwm.app. Before the first edit it saves a copy next to the file, ending in `.mielwm-backup`, and never overwrites that copy.

mielwm asks before it edits the file and before it relaunches Barik. If you move mielwm.app later, it updates that line the next time it starts.

### Turning it off

Turn the switch off. mielwm puts Barik's old `aerospace.path` back, or removes the line if there wasn't one, quits the helper and relaunches Barik. This works from any copy of mielwm, even after you moved it. If you plan to uninstall mielwm, turn the switch off first.

### Good to know

- Floating windows don't belong to a workspace, so Barik doesn't list them.
- The real AeroSpace and its `aerospace` command stay untouched, so you can go back to AeroSpace any time.
- Barik Enhanced asks for updates every 5 seconds, which costs nothing you'd notice. The original Barik asks ten times a second, which adds up to about a fifth of a CPU core. [Performance](performance.md#with-barik) has the details.
