# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

[Open an issue](https://github.com/mielsense/mielwm/issues/new/choose) with your macOS version, what you did, what you expected and what happened. The output of `mielwm state` and `mielwm --list-windows --json` shows how mielwm saw your windows, which often explains a bug on its own.

## Working on the code

### Building

You need macOS 15 or later and the Command Line Tools (`xcode-select --install`). Xcode works too, but isn't required.

```sh
swift build && swift test     # build and run the tests
scripts/build-app.sh          # build/mielwm.app, signed
scripts/build-app.sh --install # also copy it to ~/Applications and reopen it
scripts/build-app.sh --dmg    # also build/mielwm-<version>.dmg
```

`build-app.sh` signs with a self-signed "mielwm Dev" identity that it creates the first time it runs, in its own keychain at `~/Library/Keychains/mielwm-dev.keychain-db`. macOS ties the Accessibility and Screen Recording permissions to that signature, so they survive rebuilds. The keychain's password is random and kept in your login keychain, so no other user can sign as mielwm. A program running as you can still read it with the `security` tool, the price of a build that never asks for your password. If the identity can't be used, the script signs ad hoc and says so, and macOS then asks for both permissions again after every rebuild.

`build-app.sh` also tells the linker which SDK the app was built with. Plain `swift build` doesn't: SwiftPM records the deployment target, macOS 15, as the SDK, so macOS 26 and later draw a debug build's windows in the old look, without the glass sidebar or the new grouped rows. The code picks its macOS 26 paths by the running system, so a debug build on macOS 26 mixes the two. Check how Settings looks with `--settings-preview` from `build/mielwm.app`, not from `.build/debug`.

### How the code is laid out

The package has five modules and three executables.

`MielCore` is the logic, and it's pure: no AppKit, no windows, no timers. Everything the app knows lives in `CanvasState`, and every event (a key, a window moving, a tick of the clock) goes through one function that returns the window moves to make. Workspaces, tiling, the camera, search, the overview's keys, the configuration format and the AeroSpace import are all here, and so are most of the tests.

`MielRender` draws the overview with Metal: the lens, window pictures, the search panel, the help sheet and the minimap. It reads a `Scene` from `MielCore` and knows nothing else.

`MielSystem` talks to macOS: Accessibility for moving windows, the event taps for shortcuts and swipes, ScreenCaptureKit for window pictures, displays, the file watcher and the link to Barik.

`MielIPC` is the socket protocol the app, the `mielwm` command and the `aerospace` command share. It uses only Foundation, so the `aerospace` command starts fast.

`mielwm` is the app. It wires the modules together, owns the overlay windows, the Settings window, the menu bar item and onboarding, and is also the `mielwm` command-line tool. `mielwm-aerospace` is the `aerospace` command Barik runs, and also the hidden AeroSpace helper app ([AeroSpace and Barik](docs/aerospace.md)). `mielwm-testwindows` opens throwaway windows for tests.

### Testing without touching your windows

A window manager under test moves windows, so the tools are built to stay away from yours.

```sh
swift test                     # pure logic, rendering and the system layer
scripts/system-test.sh         # opens throwaway windows and checks parking,
                               # unparking, adoption and quitting end to end
scripts/benchmark.sh           # CPU and memory, the numbers in docs/performance.md
scripts/barik-test.sh          # Barik's own AeroSpace code against a test copy
```

- `mielwm snapshot --state overview|search:<text>|help|switcher|desktop [--light|--dark] --out x.png` draws any state of the overview to a PNG from made-up windows. `--real` uses your windows' pictures but still moves nothing.
- `mielwm --settings-preview --out <dir>` saves every Settings pane, the onboarding and the menu as PNGs in light and dark, on a copy of your config. `--selftest` drives the Settings window through its controls instead.
- `mielwm --manage-only <pid>` manages one app's windows only, with no shortcuts and no focus changes. Point it at `mielwm-testwindows` to try something live. `MIELWM_SOCKET`, `MIELWM_CONFIG_DIR` and `MIELWM_TEST_OVERLAY=1` give the test copy its own socket and settings and turn on its overlay. Always set `MIELWM_SOCKET` on commands you send to it, or they reach the mielwm you use.

> Never run a development build in normal mode while your own mielwm runs: two copies would fight over your windows.

### The website

The site in `website/` is SvelteKit, deployed on Vercel. Its docs pages are built from the Markdown files in `docs/`, so the docs have one source. `docs/README.md` is the index the sidebar follows.

```sh
cd website
pnpm install
pnpm dev
```

### Releases

Releases are built by GitHub Actions. To make one:

1. In `CHANGELOG.md`, rename `## Unreleased` to `## <version>`, add a `Released <date>.` line under it, and start a new `## Unreleased` above it.
2. Tag the commit and push the tag: `git tag v0.2.0 && git push origin v0.2.0`.

The release workflow runs the tests, signs the app with the "mielwm Dev" identity from the repository's secrets, builds the DMG, checks the signature on the app inside it, and publishes `mielwm-<version>.dmg`, `mielwm.dmg` (the name the website links to), a zip and `SHA256SUMS`, with that changelog section as the notes. A tag with a suffix, like `v0.2.0-rc.1`, becomes a pre-release, which the website's download link skips.

The workflow refuses to sign with any other identity, so every release keeps the same signature and users keep their permissions across updates. It reads three settings: the secrets `MIELWM_SIGNING_P12` (the identity, base64) and `MIELWM_SIGNING_P12_PASSWORD`, and the variable `MIELWM_CERT_SHA1` (the certificate's SHA-1, as shown by `codesign -dr - mielwm.app`).

mielwm isn't notarized, because that needs an Apple Developer ID. The first open on a new Mac goes through System Settings > Privacy & Security > Open Anyway.

## Before you open a pull request

- `swift build` and `swift test` pass, and so does `scripts/system-test.sh` if you touched window handling.
- New logic has a test. Most of it lives in `MielCore`, which is pure and easy to test.
- The change does one thing. Refactors and fixes go in separate pull requests.
- Docs in `docs/` say what changed for users, in plain words.
- If users can notice the change in the app, `CHANGELOG.md` has a line for it under `## Unreleased`. Website, docs and CI changes don't go there.

## Licensing

By contributing, you agree that your work is released under the [MIT License](LICENSE).
