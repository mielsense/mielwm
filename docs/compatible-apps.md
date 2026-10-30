# AeroSpace-compatible apps

Menu bars and widgets built for AeroSpace can show mielwm's workspaces and switch between them, with no plugin to install.

## How it works

An AeroSpace-compatible app learns about your workspaces by running the `aerospace` command, like `aerospace list-workspaces --all --json`, and switches by running `aerospace workspace 3`. mielwm.app holds its own `aerospace` command that answers the same questions from mielwm:

```
/Applications/mielwm.app/Contents/Helpers/aerospace
```

Point the app at that command instead of AeroSpace's, and it shows mielwm's workspaces and the windows on each. Clicking a workspace or a window switches to it. [Command line](command-line.md#the-aerospace-command) lists every command it answers.

## Turning it on from Settings

Settings > AeroSpace & Barik > Work with Barik sets this up for a supported menu bar app on its own:

1. Open the menu bar app at least once, so it writes its config file.
2. Make sure mielwm runs from your Applications folder. From the disk image or straight from Downloads, the switch asks you to move it first, because that copy disappears when mielwm quits.
3. Turn on Work with Barik, and confirm.

The menu bar app relaunches, and a few seconds later it shows mielwm's workspaces. mielwm's own menu bar item switches from All workspaces to Icon, so the numbers don't show twice.

### What it changes on your Mac

- mielwm sets one line in the app's config file, `aerospace.path`, to its own `aerospace` command. Before the first edit it saves a copy next to the file, ending in `.mielwm-backup`, and never overwrites that copy.
- A tiny hidden helper app named AeroSpace runs while the switch is on, because some apps only ask when they see AeroSpace running. It quits by itself when mielwm quits.

mielwm asks before it edits the file and before it relaunches the app. If you move mielwm.app later, it updates that line the next time it starts.

### Turning it off

Turn the switch off. mielwm puts the app's old `aerospace.path` back, or removes the line if there wasn't one, quits the helper and relaunches the app. This works from any copy of mielwm, even after you moved it. If you plan to uninstall mielwm, turn the switch off first.

## Other apps

Any other app or script that runs `aerospace` works too. Change the path it runs to mielwm's command. A status bar plugin script, for example:

```sh
AEROSPACE=/Applications/mielwm.app/Contents/Helpers/aerospace
"$AEROSPACE" list-workspaces --focused --json
```

If the app only runs `aerospace` from your `PATH`, link mielwm's command there instead:

```sh
ln -s /Applications/mielwm.app/Contents/Helpers/aerospace ~/.local/bin/aerospace
```

That link hides AeroSpace's own command if you have it installed, so remove the link before you go back to AeroSpace.

An app that also waits for an app called AeroSpace to be running needs the hidden helper, which only runs while the switch in Settings is on.

## Good to know

- Floating windows don't belong to a workspace, so the app doesn't list them.
- When mielwm isn't running, the command prints what an AeroSpace with no windows would, so the app shows nothing instead of an error.
- The real AeroSpace and its `aerospace` command stay untouched, so you can go back to AeroSpace any time.
- How often the app asks decides what it costs. Every 5 seconds costs nothing you'd notice. Ten times a second adds up to about a fifth of a CPU core. [Performance](performance.md#with-aerospace-compatible-apps) has the numbers.
