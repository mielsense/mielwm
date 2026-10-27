# AeroSpace and Barik

Move your AeroSpace setup over, and keep using Barik's workspace widget with mielwm.

## Coming from AeroSpace

mielwm's defaults follow AeroSpace's: `⌥1`…`⌥9` for workspaces, `⌥⇧1`…`⌥⇧9` to move a window, `⌥/` and `⌥,` for tiles and accordion (mielwm calls it a stack), the same arrows for focus and moving, 8 and 12 point gaps. The model is close too. A workspace tiles its windows, a window can float, and apps can be sent to a fixed workspace. What's different is the canvas around it: every workspace sits on one surface you can zoom out of ([the overview](overview.md)).

Some AeroSpace keys work differently or aren't there yet:

- `⌥Tab` is mielwm's recent-windows switcher, not `workspace-back-and-forth`.
- `⌥⇧Tab` (move a workspace to another monitor) has no equivalent yet.
- There are no binding modes like AeroSpace's service mode, and no nested containers. A workspace is tiles or a stack, one level deep.

Quit AeroSpace before you start mielwm, because two window managers fight over the same windows. mielwm offers to do it and waits until AeroSpace is gone. Set `start-at-login = false` in your AeroSpace config so it stays gone.

## Import your AeroSpace config

Settings > Layout & workspaces > Import from AeroSpace reads `~/.config/aerospace/aerospace.toml` (or `~/.aerospace.toml`), shows what it found, and applies it when you confirm:

- `[gaps]`, including the per-monitor form, where `monitor."built-in"` becomes the built-in display's top gap and the plain value the other displays'
- `default-root-container-layout` (`accordion` becomes stack) and `default-root-container-orientation`
- `[[on-window-detected]]` blocks with `if.app-id` and `run = "move-node-to-workspace N"` (a workspace rule) or `run = "layout floating"` (a floating app)
- `[mode.main.binding]` keys whose command mielwm has: `focus`, `move`, `workspace N|next|prev`, `move-node-to-workspace N` (also first in a list), `layout tiles|accordion|floating`, `fullscreen` and `resize smart ±N`

The very first time mielwm starts, before any config exists, it imports the gaps, layout and rules on its own and tells you. It leaves the keys alone, since the defaults already match AeroSpace's.

## Barik

[Barik](https://github.com/mocki-toki/barik) is a menu bar that shows your AeroSpace or yabai workspaces and switches on click. mielwm can feed it without any change to Barik.

Turn on Settings > Layout & workspaces > Work with Barik. Barik only looks for a running app called AeroSpace and asks the `aerospace` command for workspaces and windows. So when the switch is on, mielwm does two things:

- It runs a tiny hidden helper named AeroSpace, which quits on its own when mielwm does.
- It sets `aerospace.path` in Barik's config to the `aerospace` command inside mielwm.app. mielwm edits the config file Barik already uses (`~/.barik-config.toml` or `~/.config/barik/config.toml`) in place, keeps a backup next to it, and asks you first. If Barik has never run and has no config yet, open Barik once, then turn the switch on.

Barik checks for AeroSpace only when it starts, so mielwm relaunches Barik when you turn the switch on or off. It asks before doing that too. From then on Barik shows mielwm's workspaces and the windows on each, and clicking one switches to it.

Barik asks the `aerospace` command about 40 times a second. mielwm's command is a small program built for that, which answers from mielwm's current state and exits. [Performance](performance.md) has what it costs.

Turning the switch off puts Barik's old `aerospace.path` back (or removes the line), quits the helper and relaunches Barik.

The real AeroSpace command in `/opt/homebrew/bin` isn't touched, so AeroSpace keeps working if you go back to it.
