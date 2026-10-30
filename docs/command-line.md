# Command line

The `mielwm` command controls the running app from a terminal, a script or another tool.

## Installing the command

Settings > Advanced > Command-line tool links it into `~/.local/bin`. If that folder isn't on your `PATH` yet, add it. Or make the link yourself:

```sh
ln -s /Applications/mielwm.app/Contents/MacOS/mielwm ~/.local/bin/mielwm
```

## Talking to the app

```sh
mielwm workspace 3            # go to workspace 3
mielwm move-to-workspace 2    # move the focused window there
mielwm overview               # zoom out, or back in
mielwm search notes           # open the overview with a search
mielwm layout stack           # stack the current workspace
```

Every action you can bind to a key also works here:

| Action | What it does |
| --- | --- |
| `overview` | Zoom out to the overview, and back. |
| `search [text]` | Open the overview, optionally with a search. |
| `settings` | Open Settings. |
| `help` | Show every key in the overview. |
| `workspace 1`…`9`, `workspace next`, `workspace prev` | Go to a workspace. |
| `move-to-workspace 1`…`9` | Move the focused window to a workspace and go with it. |
| `layout tiles`, `layout stack`, `layout floating` | Change the layout, or float the window. |
| `focus left\|right\|up\|down` | Focus the nearest window that way. |
| `nudge left\|right\|up\|down` | Move the window that way. |
| `switch next`, `switch prev` | The recent-windows switcher. |
| `fill`, `fullscreen`, `pin` | Fill the screen, go fullscreen, pin the window. |
| `grow`, `shrink` | Resize the window. |
| `pan left\|right\|up\|down`, `zoom in`, `zoom out` | Move the camera. |
| `fit`, `frame` | Fit every window, or frame the selected one. |
| `summon`, `land`, `back` | Bring the selection here, go to it, or go back. |
| `arrange`, `undo`, `redo` | Tidy floating windows, undo, redo. |
| `refresh` | Read every app's window list again and put every window back where the canvas says. |

## Other commands

| Command | What it does |
| --- | --- |
| `mielwm` | Run the app, the same as opening mielwm.app. |
| `mielwm state` | The canvas as JSON: windows, frames, the camera. |
| `mielwm quit` | Quit, with every window back on a screen. |
| `mielwm --unpark` | Put every window from the last layout back on a screen, for after a crash. |
| `mielwm --list-windows [--json]` | The windows mielwm can see and move. |
| `mielwm --help` | Every command and option. |

When mielwm isn't running, a command says so and exits with an error, so scripts can tell.

## From other tools

Anything that can run a shell command can drive mielwm: Raycast script commands, Shortcuts, skhd, Hammerspoon, a key in BetterTouchTool. Point it at the full path, `~/.local/bin/mielwm`, because those tools often don't read your shell's `PATH`.

```sh
~/.local/bin/mielwm search slack   # open the overview, already searching for Slack
```
