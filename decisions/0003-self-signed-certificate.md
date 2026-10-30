# 0003. A self-signed certificate

Accepted. Recorded October 2026.

## Context

mielwm needs two permissions, Accessibility and Screen Recording. macOS ties both to the app's code signature. An ad hoc signature changes with every build, so every update would ask every user to grant both again. A Developer ID certificate from Apple would keep the signature stable and allow notarization, but it needs a paid Apple Developer membership, renewed every year.

## Decision

mielwm signs with a self-signed code-signing identity called "mielwm Dev". Every release uses the same certificate, SHA-1 `a56a7b9ea12cb67bfe414d2bb467d5d4bd0de056`. The release workflow refuses to publish an app signed with anything else. Local builds create their own "mielwm Dev" identity the first time `scripts/build-app.sh` runs, in a keychain of their own, so a developer's permissions also survive rebuilds.

## Consequences

- Users grant the permissions once, and they carry over to every update.
- The app isn't notarized. The first open on a new Mac goes through System Settings > Privacy & Security > Open Anyway, and the README and the release notes say so.
- The certificate can never change. A new one would make macOS ask every user for both permissions again. [RELEASING.md](../RELEASING.md) covers where the identity lives and how to keep it safe.
- A local build is signed with a different "mielwm Dev" identity than a release. Switching between a release and a local build on the same Mac asks for the permissions again.
