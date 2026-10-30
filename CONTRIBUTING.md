# Contributing

Bug reports, ideas and pull requests are all welcome. This file holds the rules for changing mielwm: how to build and test it, how to write commits and pull requests, and what gets a pull request merged.

Three other files go deeper. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the code fits together, [DESIGN.md](DESIGN.md) how the app looks, and [RELEASING.md](RELEASING.md) how a version ships. Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

## Asking and reporting

- A question about using mielwm: read the [docs](https://wm.miel.my/docs) and [Troubleshooting](docs/troubleshooting.md) first, then [open a question](https://github.com/mielsense/mielwm/issues/new?template=question.yml).
- A bug: [open a bug report](https://github.com/mielsense/mielwm/issues/new?template=bug.yml) with your mielwm and macOS versions, what you did, what you expected and what happened.
- An idea: [open a feature request](https://github.com/mielsense/mielwm/issues/new?template=feature.yml) that says what you want to do and how you do it today.
- A security problem: never in a public issue. [SECURITY.md](SECURITY.md) says where it goes.

Two commands show how mielwm saw your windows, which often explains a bug on its own. `mielwm state` prints what the running app thinks, and `mielwm --list-windows --json` lists every window Accessibility reports. mielwm also logs to the unified log, without window titles:

```sh
log show --last 10m --predicate 'subsystem == "my.miel.mielwm"'
```

For anything bigger than a small fix, open an issue before you write the code, so we can agree on the approach first.

## Building

You need macOS 15 or later and the Command Line Tools (`xcode-select --install`). Xcode works too, but isn't required. The website needs Node 22 and pnpm.

Every command you need is in this list:

```sh
swift build && swift test        # build, then run every test
scripts/build-app.sh             # build/mielwm.app in release mode, signed
scripts/build-app.sh --install   # also copy it to ~/Applications, reopening it if it ran
scripts/build-app.sh --dmg       # also build/mielwm-<version>.dmg
scripts/e2e.sh                   # every end-to-end test below, each after 30 s of idle
scripts/system-test.sh           # throwaway windows, end to end
scripts/barik-test.sh            # a status bar's AeroSpace code against a test copy
scripts/benchmark.sh             # CPU and memory, the numbers in docs/performance.md
swift scripts/make-icon.swift    # redraw the app icon and menu bar glyph in Resources/

cd website && pnpm install && pnpm dev     # the website, with live reload
cd website && pnpm check && pnpm build     # what CI runs on the website
```

`build-app.sh` signs with a self-signed "mielwm Dev" identity that it creates the first time it runs, in its own keychain at `~/Library/Keychains/mielwm-dev.keychain-db`. macOS ties the Accessibility and Screen Recording permissions to that signature, so they survive rebuilds. The keychain's password is random and kept in your login keychain, so no other user can sign as mielwm. A program running as you can still read it with the `security` tool, the price of a build that never asks for your password. If the identity can't be used, the script signs ad hoc and says so, and macOS then asks for both permissions again after every rebuild. [Decision 0003](decisions/0003-self-signed-certificate.md) explains why it works this way.

`build-app.sh` also tells the linker which SDK the app was built with. Plain `swift build` doesn't. SwiftPM records the deployment target, macOS 15, as the SDK, so macOS 26 and later draw a debug build's windows in the old look, without the glass sidebar or the new grouped rows. The code picks its macOS 26 paths by the running system, so a debug build on macOS 26 mixes the two. Check how Settings looks with `--settings-preview` from `build/mielwm.app`, not from `.build/debug`.

## Testing without touching your windows

A window manager under test moves windows, so the tools stay away from yours. Never run a development build in normal mode while your own mielwm runs. Two copies fight over every window.

- `swift test` runs the pure logic, the renderer, the socket, the system layer and the app's own logic. It moves nothing. On CI each test target runs in its own process: `swift test --skip-build --filter MielCoreTests`, and so on for `MielRenderTests`, `MielIPCTests`, `MielSystemTests` and `mielwmTests`.
- `mielwm snapshot --state overview|search:<text>|help|switcher|desktop [--light|--dark] --out x.png` draws any state of the overview to a PNG from made-up windows, with the chrome in its solid Reduce Transparency material, since Liquid glass only draws on screen. `--real` uses your windows' pictures but still moves nothing.
- `mielwm --settings-preview --out <dir>` saves every Settings pane, the onboarding and the menu as PNGs in light and dark, on a copy of your config. `--selftest` drives the Settings window through its controls instead.
- `mielwm --manage-only <pid>` manages one app's windows only, with no shortcuts and no focus changes. Point it at `mielwm-testwindows` to try something live.
- `scripts/system-test.sh`, `scripts/barik-test.sh` and `scripts/benchmark.sh` do exactly that for you, each with its own socket and settings, and clean up after themselves.

Every test copy gets its own `MIELWM_SOCKET` and `MIELWM_CONFIG_DIR`, and `MIELWM_TEST_OVERLAY=1` turns on its overlay. Set `MIELWM_SOCKET` on every `mielwm` command you send to a test copy too. Without it, the command reaches the mielwm you use.

### End to end

`scripts/e2e.sh` runs every test that puts windows on screen, one after another. Each part first waits until nobody has touched the keyboard or the mouse for 30 seconds, so start it and leave the Mac alone.

- `MIELWM_SYSTEM_TESTS=1 swift test --filter WindowTests` drives throwaway windows through the system layer: reading and moving them, parking, minimizing, closing, hidden apps, rescans, a hung app, window pictures and the event tap.
- `scripts/system-test.sh` drives a test copy from the command line. With floating windows it pans until they park and back, and adopts a move the app makes itself. With tiles it switches workspaces, focuses, moves a window to another workspace, stacks, tiles and floats, closes and minimizes, opens, searches and closes the overview and checks it keeps drawing, rescans, answers the `aerospace` command and quits with every window back on screen.
- `scripts/barik-test.sh` runs a status bar's own AeroSpace code against a test copy.

The checks wait for a condition, like a window being parked, instead of sleeping, and fail after a few seconds without it. `mielwm state` reports what they read, including `settled` once nothing moves and `framesDrawn` for the overlay.

Run `scripts/e2e.sh` when you change window handling, and `scripts/benchmark.sh` before and after a change meant to make mielwm faster or lighter.

## Where a change goes

[ARCHITECTURE.md](ARCHITECTURE.md) maps every module and the path an event takes through them. The short version:

- New behaviour goes in `Sources/MielCore` first, with its tests. It's pure, so it's easy to test.
- `MielCore` never imports AppKit and never touches windows, timers or the clock. Time comes in as an input.
- Match the file you're in. Files are small, with one concern each.
- Log with `log(_:)` from `MielSystem`. Never log window titles.
- Every API must exist on macOS 15. Guard anything newer with `#available`.
- Every module builds in the Swift 6 language mode, with its strict concurrency checks. A callback that runs on the main thread says so with `@MainActor`, and one that crosses threads is `@Sendable`. `@unchecked Sendable` and `nonisolated(unsafe)` need a comment that says why they are safe.
- The app takes no new dependencies. A test-only dependency is fine when it saves real work.

## Commits

Commits follow [Conventional Commits](https://www.conventionalcommits.org), written for someone reading `git log` a year from now. CI checks the format of every commit in a pull request.

```text
fix(settings): keep the edited gap lit when the pointer leaves another

While typing in one gap field, pointing at another and moving away
cleared the highlight. The diagram now falls back to the field being
edited.
```

- The subject is `type(scope): what changed`, in lowercase, with no period, in 72 characters or fewer.
- Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `style`, `build`, `ci`, `chore`.
- The scope is an area from [labels.yml](.github/labels.yml) without its `area: ` prefix, like `settings` or `website`, or `macos` for a quirk of one macOS version. Leave it out when none fits.
- The body says why, in plain sentences. The diff already shows what.
- One change per commit. A refactor and the fix it made possible are two commits.
- Before you commit, run `swift build && swift test`, `pnpm check` in `website/` if you touched it, and actionlint if you touched `.github/workflows/`.
- No `Co-Authored-By` trailers, no "Generated with" lines and no tool attribution, in commits, pull requests, code or docs. CI rejects a commit that has one.
- GitHub's Apply suggestion button makes a commit titled "Apply suggestions from code review" with a `Co-authored-by` trailer, which fails both checks. Squash it into the commit it fixes, or reword it.

## Branches

Branch from the latest `main` and name the branch `<type>/<short-slug>`, with the same types as commits. For example `fix/stack-focus` or `docs/trackpad-page`. The labeler reads the prefix to pick the pull request's type label.

## Pull requests

One pull request makes one change. The [template](.github/PULL_REQUEST_TEMPLATE.md) asks for the rest.

- The title says what changes for someone using mielwm, in plain words. "Windows stay put when a display sleeps", not "fix(system): handle didWake". The title isn't a commit, so it doesn't follow the commit format.
- The body has the template's sections: what changes, why, and how you checked it.
- Docs and the changelog change in the same pull request as the behaviour they describe.
- A change you can see in the app includes screenshots, in light and dark when both differ. `mielwm snapshot` and `--settings-preview` make them without touching your screen.
- A change meant to make mielwm faster or lighter includes the `scripts/benchmark.sh` table from before and after.
- Keep the branch up to date by merging `main` into it. Don't force-push once someone has reviewed it.

### Labels

Labels sort issues and pull requests. [.github/labels.yml](.github/labels.yml) defines them, with a description for each, and a workflow keeps GitHub in step with that file.

- A type: `bug`, `feature`, `docs`, `perf`, `chore` or `question`. The labeler sets it on pull requests from the branch prefix.
- One or more areas, like `area: core` or `area: website`. The labeler sets them from the paths a pull request changes.
- A status, when one applies. `needs repro` means nobody can act until someone makes the bug happen again. `good first issue` and `help wanted` invite new contributors. `skip changelog` tells CI a change to `Sources/` or `Resources/` needs no changelog line, because nothing changes for people using the app.

Maintainers fix labels by hand when the labeler guesses wrong.

### What gets a pull request merged

A pull request is ready to merge when:

- CI is green. That's the app, the website, the link check, the workflow lint, the commit format and the changelog check. Read a failure before you re-run it.
- A maintainer has reviewed and approved it.
- New logic has a test. A bug fix has a test that fails before the fix and passes after.
- It changes one thing, follows the commit rules, and has its docs and changelog line.
- Its text follows the [writing rules](#writing), and anything on screen follows [DESIGN.md](DESIGN.md).

These block a merge:

- Breaking a rule in [Where a change goes](#where-a-change-goes).
- A test that moves real windows, posts synthetic input, or talks to a running mielwm without its own socket.
- A change to how releases are signed. See [RELEASING.md](RELEASING.md).

Maintainers merge with a merge commit, so every commit stays in the history.

## The changelog

[CHANGELOG.md](CHANGELOG.md) lists what changed in the app, for people who use it. Each version's section becomes its release notes, and the website shows the file as its Changelog page.

- Every change someone can notice in the app adds a line under `## Unreleased`, in the matching `###` area. Add the area if it doesn't exist yet.
- Leave out the website, the docs, CI, tests and refactors that change nothing for users. CI asks for a line whenever `Sources/` or `Resources/` changes, so label a refactor there `skip changelog`.
- Write each line as what the user gets: "Three-finger swipes switch workspaces", not "add SwipeRecognizer". A fix says what was broken: "Status bars keep working after mielwm.app moves."

[RELEASING.md](RELEASING.md) says how the `Unreleased` section turns into a version.

## Documentation

`docs/` is for people using mielwm. The website renders it, so it's the only copy. Material for people building mielwm goes in this file, [ARCHITECTURE.md](ARCHITECTURE.md), [DESIGN.md](DESIGN.md) or [RELEASING.md](RELEASING.md).

- `docs/README.md` is the index. Its `## Group` headings and `- [Title](page.md)` lines set the sidebar and its order, so a new page needs a line there.
- Every page starts with `# Title` and a one-line lead, then `##` and `###` sections. Links between pages are relative, like `keyboard.md#section`. CI checks every link and anchor.
- Screenshots go in `docs/images/` as `name-dark.png`, with a `name-light.png` sibling when there is one. The site swaps them with its theme.
- When behaviour changes, update the page that describes it. Say what the user sees and does, with real key names, menu paths and numbers. Leave out how it's built, what it used to be and how it got there.

## Writing

Everything you write for mielwm reads like a person wrote it: docs, the changelog, commits, pull requests, comments and text in the app.

- Plain words. "Use", not "utilize". Say what something does, with a number or a name, instead of how it feels.
- Short sentences, one idea each, in the active voice.
- No em dashes or en dashes, and few parentheses. Use a period or a comma.
- Colons only before a list or an example.
- Sentence case for headings. Straight quotes. No emoji.
- No filler ("it's important to note"), no puffery ("seamless", "powerful", "robust") and no chatbot phrases.
- Name other apps only as examples. Barik is one AeroSpace-compatible status bar. Don't name a new feature, setting or pane after another app. The config key `integrations:barik` keeps its name so existing config files keep working.

Text inside the app has a few more rules, in [DESIGN.md](DESIGN.md#text).

## The website

The site in `website/` is SvelteKit 2, Svelte 5, Tailwind 4 and `@mielui/svelte`, deployed on Vercel at [wm.miel.my](https://wm.miel.my). Use `pnpm`.

- It reads `docs/*.md` and `CHANGELOG.md` when it builds. Never copy their text into the site.
- The look is settled. No page frames, no borders where colour or translucency already separates things, solid high-contrast controls, and colour in headers, icons and cards. Docs pages have no header bar.
- Text meets WCAG AA contrast, 4.5:1, including on the colour meshes.
- Pull requests get a Vercel preview. Production deploys need the maintainer's go-ahead.

## Continuous integration

[ci.yml](.github/workflows/ci.yml) runs on every push to `main` and every pull request. [pull-request.yml](.github/workflows/pull-request.yml) checks commit messages and the changelog. A few things about it are easy to trip over:

- Each test target runs in its own process. With Xcode, all targets share one process, and the render tests starve the main queue.
- Low-priority dispatch work can stall for 30 seconds or more on GitHub's macOS runners. A test that waits on it skips on CI with `.disabled(if: CI)` and tests the logic directly.
- A job-level `env` can't read `runner.*`. Set those values from a step through `$GITHUB_ENV`.
- Actions are pinned to a commit SHA with a `# vN` comment. Dependabot keeps them current.
- CI counts compiler warnings and lists them in the build log. Setting `WARNINGS_AS_ERRORS` to `true` at the top of `ci.yml` makes any warning fail the build.

To lint the workflows before you push, run [actionlint](https://github.com/rhysd/actionlint) from the repository root.

## Licensing

By contributing, you agree that your work is released under the [MIT License](LICENSE).
