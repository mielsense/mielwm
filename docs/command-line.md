# Command line

The `mielwm` command controls the running app from a terminal, a script or another tool.

## Installing the command

Settings > Advanced > Command-line tool > Install links it into `~/.local/bin`. If that folder isn't on your `PATH` yet, add it. Or make the link yourself:

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
mielwm resize width +100      # make the focused window 100 points wider
```

When mielwm isn't running, a command says so and exits with status 2, so scripts can tell. An action the running app can't take exits with status 1.

## Actions

Every action you can bind to a key also works here, and the same words go after `keys:<chord>` in the [configuration file](configuration.md#shortcuts).

| Action | What it does |
| --- | --- |
| `overview` | Zoom out to the overview, and back. |
| `search [text]` | Open the overview, optionally with a search. |
| `help` | Show every key in the overview. |
| `settings` | Open Settings. |
| `workspace 1`…`9` | Go to a workspace. |
| `workspace next`, `workspace prev` | The next or previous workspace that has windows. |
| `workspace-back-and-forth` | Go to the workspace you were on before. |
| `move-to-workspace 1`…`9` | Move the focused window to a workspace and go with it. `move-node-to-workspace` works too. |
| `layout tiles`, `layout stack`, `layout floating` | Tile or stack the workspace, or float the focused window. `layout accordion` means `stack`. |
| `focus left\|right\|up\|down` | Focus the nearest window that way. |
| `nudge left\|right\|up\|down` | Move the window that way: swap tiles, or nudge a floating window. |
| `switch next`, `switch prev` | The recent-windows switcher. |
| `fill`, `fullscreen`, `pin` | Fill the screen, fill it with no gaps, pin the window. |
| `grow`, `shrink` | Resize the window by one step. |
| `resize smart\|width\|height +N\|-N` | Resize by `N` points. See below. |
| `close`, `minimize` | Close the window, or minimize it to the Dock. |
| `arrange` | Tidy the floating windows. |
| `undo`, `redo` | Undo or redo moves and tidying in the overview. |
| `pan left\|right\|up\|down`, `zoom in`, `zoom out` | Move the overview's camera. |
| `fit`, `frame` | Fit every window, or frame the selected one. |
| `summon`, `land`, `back` | Bring the selected window here, go to it, or go back. |
| `refresh` | Read every app's window list again and put every window back where the canvas says. |
| `noop` | Nothing. Bind a key to it so it never reaches an app. |

### Resize

`resize` takes a side and a signed amount, like AeroSpace's:

- `resize smart +100` follows the split between tiles, or grows a floating window on both axes.
- `resize width -50` and `resize height +80` change one side.

A tile changes only along its split. With tiles side by side, `resize width` moves the split and `resize height` does nothing. A floating window grows around its center and never gets smaller than 160 by 100 points. AeroSpace's `resize width 800`, which sets a size, isn't supported.

## Other commands

| Command | What it does |
| --- | --- |
| `mielwm` | Run the app, the same as opening mielwm.app. |
| `mielwm state` | The canvas as JSON: windows, frames, the camera. |
| `mielwm quit` | Quit, with every window back on a screen. |
| `mielwm --unpark` | Put every window from the last layout back on a screen, for after a crash. |
| `mielwm --list-windows [--json]` | The windows mielwm can see and move, with their app and title. |
| `mielwm --help` | Every command and option. |

## The aerospace command

mielwm.app also holds a small `aerospace` command, at `/Applications/mielwm.app/Contents/Helpers/aerospace`. Menu bar apps that read AeroSpace's workspaces run it in place of AeroSpace's own. It answers from the running mielwm:

| Command | What it does |
| --- | --- |
| `aerospace list-workspaces --all --json` | The workspaces that have windows, as `[{"workspace": "1"}, …]`. |
| `aerospace list-workspaces --focused --json` | The current workspace. |
| `aerospace list-windows --all --json` | Every window on a workspace, with `window-id`, `app-name`, `window-title` and `workspace`. Floating windows aren't listed. |
| `aerospace list-windows --focused --json` | The focused window. |
| `aerospace workspace N` | Go to workspace N. |
| `aerospace focus --window-id ID` | Go to that window. |
| `aerospace focus left\|right\|up\|down` | Focus the nearest window that way. |
| `aerospace workspace-back-and-forth`, `close`, `macos-native-minimize` | The same as mielwm's actions. |
| `aerospace resize smart\|width\|height +N\|-N` | The same as `mielwm resize`. |

It waits at most 0.3 seconds for mielwm. When mielwm isn't running, or the command is one it doesn't know, it prints what an AeroSpace with no windows would: `[]` for a list, nothing for an action. [AeroSpace-compatible apps](compatible-apps.md) explains how to point an app at it.

## From other tools

Anything that can run a shell command can drive mielwm: Raycast script commands, Shortcuts, skhd, Hammerspoon, a key in BetterTouchTool. Point it at the full path, `~/.local/bin/mielwm`, because those tools often don't read your shell's `PATH`.

```sh
~/.local/bin/mielwm search slack   # open the overview, already searching for Slack
```
