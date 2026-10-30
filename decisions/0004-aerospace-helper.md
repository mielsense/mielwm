# 0004. A helper that answers as AeroSpace

Accepted. Recorded October 2026.

## Context

Status bars like Barik show AeroSpace's workspaces. They look for a running app called AeroSpace, and they ask about workspaces by running the `aerospace` command, several times every few seconds. People moving from AeroSpace want their status bar to keep working, without a plugin or a change to the status bar.

## Decision

One small executable, `mielwm-aerospace` in [Sources/MielAeroSpace](../Sources/MielAeroSpace), does two jobs. Installed as `Contents/Helpers/aerospace`, it answers AeroSpace commands by asking the running mielwm over the socket. Installed as the hidden `Contents/Helpers/AeroSpace.app`, it runs while mielwm runs, so the status bar finds an app called AeroSpace, and it quits when mielwm does. mielwm points the status bar's config at the command, after asking, and keeps a backup of the file.

## Consequences

- The status bar works unchanged. The setup is one switch in Settings, and turning it off restores the config.
- The command must start fast, because it runs so often. It links only `MielIPC` and Foundation, no AppKit, and gives up after 0.3 seconds. With no answer, or a command mielwm doesn't know, it prints what an AeroSpace with no windows would.
- mielwm edits a file that belongs to another app, so it asks first, backs the file up before the first edit, and never overwrites that backup.
- The helper's name collides with the real AeroSpace. mielwm and AeroSpace can't run together anyway, and mielwm asks to quit AeroSpace before it starts.
- `scripts/barik-test.sh` runs Barik's own AeroSpace code against a test copy, so a change to the protocol that would break a status bar fails there.
