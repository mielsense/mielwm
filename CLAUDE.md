# mielwm

A tiling window manager for macOS. Windows tile into numbered workspaces the way AeroSpace does it, all on one endless canvas you can zoom out of to see every window as a live picture. It's a Swift package for macOS 15 and later, plus a SvelteKit website in `website/`.

Read this before you change anything. The first section is not optional.

## Never touch the real windows

A window manager under test moves windows. The person working with you is using their Mac right now, and a bad run can scramble or freeze it.

- Never run mielwm in normal mode: no `mielwm` with no arguments, no `open mielwm.app`, no `build/mielwm.app`. A second copy fights the one they use over every window.
- Their own mielwm is probably running. Every `mielwm` command you send carries its own socket, `MIELWM_SOCKET=/tmp/<something>.sock`, or it reaches their app. Test copies also get their own `MIELWM_CONFIG_DIR`.
- Never post synthetic input: no CGEvent posting, no AppleScript keystrokes, no clicking through the UI to test.
- Anything that puts windows or overlays on screen waits until the user has been idle for 30 seconds:
  `ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'` must print 30 or more. Wait inside one shell loop.
- Don't touch their AeroSpace config, Barik or its config, system settings, or `~/Applications/mielwm.app`. `scripts/build-app.sh --install` replaces their app, so only run it when they ask.

Safe to run any time: `swift build`, `swift test`, `.build/debug/mielwm snapshot …`, `--settings-preview` with its own socket and config dir, and `--manage-only <pid>` pointed at `mielwm-testwindows`.

## Commands

```sh
swift build && swift test        # build and run every test
scripts/build-app.sh             # build/mielwm.app, signed with the "mielwm Dev" identity
scripts/system-test.sh           # throwaway windows, end to end (idle wait first)
scripts/barik-test.sh            # Barik's own code against a test copy (idle wait first)
scripts/benchmark.sh             # CPU and memory on a test copy

cd website && pnpm install && pnpm check && pnpm build
```

## Where things live

- `Sources/MielCore` is the logic, and it's pure: no AppKit, no windows, no timers. Every event goes through one reducer that returns the window moves to make. New behaviour goes here first, with its tests.
- `Sources/MielRender` draws the overview with Metal from a `Scene`. It knows nothing else.
- `Sources/MielSystem` talks to macOS: Accessibility, event taps, ScreenCaptureKit, displays, the file watcher, Barik.
- `Sources/MielIPC` is the socket protocol. Foundation only, because the `aerospace` command must start fast.
- `Sources/mielwm` is the app and the `mielwm` command. `Sources/MielAeroSpace` is the `aerospace` command and the hidden AeroSpace helper. `Sources/MielTestWindows` opens throwaway windows.
- `docs/` is the user documentation. The website renders it, so it's the only copy.
- `website/` is the site at wm.miel.my. `CONTRIBUTING.md` explains building, testing and releases in detail.

## Code

- Match the file you're in. Small files with one concern each, the way the cleanup left them.
- Log with `log(_:)` from MielSystem. It writes to stderr and the unified log under `my.miel.mielwm`. Never log window titles.
- No new dependencies for the app. Test-only dependencies are fine when they save real work.
- APIs must exist on macOS 15. CI builds with Xcode 26 on GitHub's runners, while local builds use the Command Line Tools.
- New logic gets a test. A bug fix gets a test that fails before the fix.

## Commits

Conventional commits, written for a person reading `git log` a year from now.

- `type(scope): what changed`, lowercase, no period, under about 70 characters. Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `style`, `build`, `ci`, `chore`. Scopes in use: `website`, `barik`, `settings`, `macos`. Leave the scope out when nothing fits.
- The body says why, in plain sentences. What the diff does is already in the diff.
- One change per commit. A refactor and the fix it enabled are two commits.
- Run `swift build && swift test` before you commit, and `pnpm check` too if you touched `website/`.
- No `Co-Authored-By` trailers, no "Generated with" lines, no tool attribution anywhere: commits, PR bodies, code or docs.
- In a checkout other people or agents are also editing, commit by path (`git commit -- <paths>`), never `git add -A` across someone else's work.

## Pull requests

- Branch from the latest `main`. Name it `<type>/<short-slug>`, or `parker/<slug>` when Parker runs it.
- The title says what changes for the user, in plain words. The body follows the template: what changed, how you checked it.
- One PR per change. Docs and changelog updates for that change go in the same PR.
- CI must be green: the app job and the website job. Read a failure before re-running it.
- Never merge unless the user asks you to. When they do, use a merge commit so the individual commits stay in the history.

## The changelog

`CHANGELOG.md` lists what changed in the app, for people who use it. The release workflow publishes each version's section as its release notes, and the website shows the file as the Changelog page.

- Every change a user can notice in the app adds a line under `## Unreleased`, in the matching `###` area. Add the area if it doesn't exist yet. Do this in the same PR as the change.
- Leave out the website, the docs, CI, tests and refactors that change nothing for users. Nobody running mielwm cares that a file was split.
- Write each line as what the user gets: "Three-finger swipes switch workspaces", not "add SwipeRecognizer". Fixes say what was broken: "Barik keeps working after mielwm.app moves."
- At release time, rename `## Unreleased` to `## <version>`, add a `Released <Month day, year>.` line under it, and start a fresh `## Unreleased` with "Nothing yet." above it. The release workflow looks for a heading whose second word is the version, so keep `## 0.2.0` exactly like that.

## Docs

`docs/` is for people using mielwm, not for people building it.

- `docs/README.md` is the index. `## Group` headings and `- [Title](page.md)` lines decide the sidebar and its order. A new page needs a line there.
- Every page starts with `# Title` and a one-line lead, then `##` and `###` sections. Links between pages are relative, like `keyboard.md#section`.
- Screenshots go in `docs/images/` as `name-dark.png`, with a `name-light.png` sibling when there is one. The site swaps them with its theme.
- When behaviour changes, update the page that describes it in the same PR. Say what the user sees and does, with real key names, menu paths and numbers. Leave out how it's built, what it used to be, and development history.
- Developer material goes in `CONTRIBUTING.md`, not `docs/`.

## Writing

All prose, in docs, the changelog, commits, PRs and UI text, reads like a person wrote it.

- Plain words. "Use", not "utilize". Say what something does, with a number or a name, instead of how it feels.
- Short sentences, one idea each, active voice.
- No em dashes or en dashes, and few parentheses. Use a period or a comma.
- Colons only before a list or an example.
- Sentence case for headings. Straight quotes. No emoji.
- No filler ("it's important to note"), no puffery ("seamless", "powerful", "robust"), no chatbot phrases.
- In the app's UI, text uses SF Pro at regular or medium weight, and nothing is ever all caps.

## Website

SvelteKit 2, Svelte 5, Tailwind 4 and `@mielui/svelte`, deployed on Vercel at wm.miel.my. Use `pnpm`.

- It reads `docs/*.md` and `CHANGELOG.md` at build time. Never copy their text into the site.
- The look is settled: no page frames, no borders where colour or translucency already separates things, solid high-contrast controls, colour in headers, icons and cards. Docs pages have no header bar. Keep that look unless the user asks for something else.
- Check text contrast against WCAG AA (4.5:1), especially on the colour meshes.
- Never deploy to production without the user's go-ahead. Preview deploys are fine.

## Releases

1. Move the `## Unreleased` entries to `## <version>` as described above.
2. Merge to `main`, then tag it: `git tag -a v0.2.0 -m "mielwm 0.2.0" && git push origin v0.2.0`.
3. The release workflow tests, signs with the "mielwm Dev" identity from the repository secrets, builds the DMG, checks the signature on the app inside it and publishes the release. Tags with a suffix, like `v0.2.0-rc.1`, publish as pre-releases and make a good dry run.

Every release must be signed with the same certificate, SHA-1 `a56a7b9ea12cb67bfe414d2bb467d5d4bd0de056`. A different one makes macOS ask every user for their permissions again. The workflow refuses to publish anything else.

## CI quirks worth knowing

- Each test target runs in its own process on CI. With Xcode, all targets share one process, and the render tests starve the main queue.
- Low-priority dispatch work can stall for 30 seconds or more on GitHub's macOS runners. A test that waits on it skips on CI (`.disabled(if: CI)`) and tests the logic directly.
- A job-level `env` in a workflow can't read `runner.*`. Set those values from a step through `$GITHUB_ENV`.
- Actions are pinned to commit SHAs with a `# vN` comment. Dependabot keeps them current.
