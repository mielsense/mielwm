# mielwm

A tiling window manager for macOS. Windows tile into numbered workspaces the way AeroSpace does it, all on one endless canvas you can zoom out of to see every window as a live picture. It's a Swift package for macOS 15 and later, plus a SvelteKit website in `website/`.

This file is for coding agents, and `AGENTS.md` is a link to it. The rules for everyone, agents included, are in [CONTRIBUTING.md](CONTRIBUTING.md). Read both before you change anything. The first section here is not optional.

## Never touch the real windows

A window manager under test moves windows. The person working with you is using their Mac right now, and a bad run can scramble or freeze it.

- Never run mielwm in normal mode: no `mielwm` with no arguments, no `open mielwm.app`, no `build/mielwm.app`. A second copy fights the one they use over every window.
- Their own mielwm is probably running. Every `mielwm` command you send carries its own socket, `MIELWM_SOCKET=/tmp/<something>.sock`, or it reaches their app. Test copies also get their own `MIELWM_CONFIG_DIR`.
- Never post synthetic input: no CGEvent posting, no AppleScript keystrokes, no clicking through the UI to test.
- Anything that puts windows or overlays on screen waits until the user has been idle for 30 seconds. That's `scripts/system-test.sh`, `scripts/barik-test.sh`, `scripts/benchmark.sh`, `--settings-preview`, `--selftest`, and `--manage-only` with `mielwm-testwindows`. This must print 30 or more, checked inside one shell loop:
  `ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'`
- Don't touch their AeroSpace config, their status bar app or its config, system settings, or `~/Applications/mielwm.app`. `scripts/build-app.sh --install` replaces their app, so only run it when they ask.

Safe to run any time: `swift build`, `swift test` and `.build/debug/mielwm snapshot …`. `scripts/build-app.sh` is safe once their "mielwm Dev" keychain exists. Its first run creates that keychain, so ask before then.

## Where to look

- [CONTRIBUTING.md](CONTRIBUTING.md): every command, testing without touching windows, where a change goes, commits, branches, pull requests, labels, what gets merged, the changelog, docs, writing and the website.
- [ARCHITECTURE.md](ARCHITECTURE.md): the modules, the words the code uses, and how an event moves through the reducer. Read it before you add behaviour.
- [DESIGN.md](DESIGN.md): how anything on screen looks, and the rules for text in the app.
- [RELEASING.md](RELEASING.md): tagging, signing and what the release workflow checks.
- [decisions/](decisions/): why the big choices were made.
- `docs/`: the user documentation, which the website renders.

## Rules for agents

These cover what only an agent does. Everything else is in CONTRIBUTING.md.

- Your tool may add `Co-Authored-By` trailers or "Generated with" lines by default. Remove them everywhere. [Commits](CONTRIBUTING.md#commits) forbids them, and CI rejects them.
- In a checkout other people or agents are also editing, commit by path (`git commit -- <paths>`), never `git add -A` across someone else's work.
- Push, open pull requests, tag, publish releases and deploy the website to production only when the user asks. Never merge unless they ask, and then use a merge commit.
- Before you say you're done, run `swift build && swift test`, `pnpm check` in `website/` if you touched it, and actionlint if you touched `.github/workflows/`. Report what you ran and what you didn't.
- A change is done when it has its test, its docs page and its changelog line, as [What gets a pull request merged](CONTRIBUTING.md#what-gets-a-pull-request-merged) lists.
- Write every sentence by the [writing rules](CONTRIBUTING.md#writing), and text in the app by [DESIGN.md](DESIGN.md#text) too.
