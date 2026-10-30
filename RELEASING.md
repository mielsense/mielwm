# Releasing

How a version of mielwm gets from `main` to the download link. Only the maintainer tags releases.

## Checklist

1. Check that CI is green on `main`.
2. In `CHANGELOG.md`, rename `## Unreleased` to `## <version>`, like `## 0.2.0`. Add a `Released <Month day, year>.` line under it. Above it, start a fresh `## Unreleased` with "Nothing yet." under it.
3. Read the new section as a user would. Every line says what they get or what was broken, per the [changelog rules](CONTRIBUTING.md#the-changelog).
4. Merge that change to `main`.
5. Tag the merge and push the tag:

   ```sh
   git switch main && git pull
   git tag -a v0.2.0 -m "mielwm 0.2.0"
   git push origin v0.2.0
   ```

6. Watch the Release workflow. When it finishes, download `mielwm.dmg` from the release page and check the signature of the app inside it, not one you already have installed:

   ```sh
   hdiutil attach -nobrowse -mountpoint /tmp/mielwm-release ~/Downloads/mielwm.dmg
   codesign -dr - /tmp/mielwm-release/mielwm.app 2>&1 | grep a56a7b9ea12cb67bfe414d2bb467d5d4bd0de056
   hdiutil detach /tmp/mielwm-release
   ```

The release workflow finds the section by its heading, whose second word must be the version. Keep `## 0.2.0` exactly like that, with no "v" and nothing after it.

## What the workflow does

[release.yml](.github/workflows/release.yml) runs on every tag that starts with `v`. In order, it:

1. Takes the version from the tag, so `v0.2.0` becomes `0.2.0`.
2. Cuts that version's section out of `CHANGELOG.md` for the release notes. With no section, it stops here, before anything slow.
3. Checks that a release tag points at a commit on `main`.
4. Runs every test, one target per process.
5. Signs the app with the "mielwm Dev" identity from the repository's secrets, and builds the DMG.
6. Opens the DMG and checks that the app inside carries the expected certificate.
7. Publishes `mielwm-<version>.dmg`, `mielwm.dmg`, a zip and `SHA256SUMS`, with the changelog section as the notes. `mielwm.dmg` is the name the website's download link uses.

## Pre-releases

A tag with a suffix, like `v0.2.0-rc.1`, publishes a pre-release. The website's download link skips pre-releases, so it's a safe dry run of the whole workflow. It may come from any branch. Its notes come from its own section if there is one, then from `## 0.2.0`, then from `## Unreleased`.

## If a release fails

If the workflow fails before Publish, nothing is public yet. Delete the tag, fix the problem on `main`, and tag again:

```sh
git push --delete origin v0.2.0
git tag -d v0.2.0
```

If it failed after Publish, or the published app is broken, never reuse the version number. Users may already have it. Fix it on `main` and release the next patch version.

## Signing

Every release must be signed with the same certificate, SHA-1 `a56a7b9ea12cb67bfe414d2bb467d5d4bd0de056`. A different one makes macOS ask every user for the Accessibility and Screen Recording permissions again. [Decision 0003](decisions/0003-self-signed-certificate.md) explains why mielwm uses a self-signed certificate.

The workflow reads three repository settings:

- The secret `MIELWM_SIGNING_P12` holds the identity, base64-encoded.
- The secret `MIELWM_SIGNING_P12_PASSWORD` holds its password.
- The variable `MIELWM_CERT_SHA1` holds the certificate's SHA-1, as `codesign -dr - mielwm.app` shows it.

`scripts/build-app.sh` refuses any other certificate when `MIELWM_EXPECT_CERT_SHA1` is set, and the workflow checks the signature again on the app inside the DMG. Never change these settings to a new identity. Keep an offline copy of the `.p12` and its password, because losing them means every user grants both permissions again.

mielwm isn't notarized, because that needs an Apple Developer ID. The first open on a new Mac goes through System Settings > Privacy & Security > Open Anyway, and the release notes say so.

## Building a release yourself

The release is built from the tagged commit with nothing that isn't in the repository, apart from the signing identity. To build the same thing:

```sh
git switch --detach v0.2.0
MIELWM_VERSION=0.2.0 scripts/build-app.sh --dmg
```

- CI uses GitHub's `macos-26` runner with its default Xcode. The workflow's Toolchain step in CI prints the exact Xcode and Swift versions.
- The build number is the number of commits up to the tag, so build from a full clone, not a shallow one.
- Build with `build-app.sh`, never plain `swift build`, for the reason in [Building](CONTRIBUTING.md#building).
- Your build is signed with your own "mielwm Dev" identity, so its signature and checksums differ from the release's. Compare the code, not the bytes.

To check a download, compare it with the release's `SHA256SUMS`:

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
```
