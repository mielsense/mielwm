# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

[Open an issue](https://github.com/mielsense/mielwm/issues/new/choose) with your macOS version, what you did, what you expected and what happened. The output of `mielwm state` and `mielwm --list-windows --json` shows how mielwm saw your windows, which often explains a bug on its own.

## Working on the code

You need macOS 15 or later and the Command Line Tools (`xcode-select --install`). Xcode works too.

```sh
swift build && swift test
scripts/build-app.sh --install
```

[Development](docs/development.md) covers the layout of the code, the test tools and the rules that keep test runs away from your own windows. Read it before you run anything that manages windows.

Before you open a pull request:

- `swift build` and `swift test` pass, and so does `scripts/system-test.sh` if you touched window handling.
- New logic has a test. Most of it lives in `MielCore`, which is pure and easy to test.
- The change does one thing. Refactors and fixes go in separate pull requests.
- Docs in `docs/` say what changed for users, in plain words.

The website lives in `website/`. `pnpm install && pnpm dev` there runs it locally.

## Licensing

By contributing, you agree that your work is released under the [MIT License](LICENSE).
