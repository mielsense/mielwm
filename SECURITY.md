# Security

mielwm has Accessibility and Screen Recording access, so a security bug in it matters. Please don't report one in a public issue. Use [GitHub's private vulnerability reporting](https://github.com/mielsense/mielwm/security/advisories/new) instead, and I'll answer as soon as I can.

A useful report says which version you tested, what an attacker can do, and the steps to do it.

Some areas matter most:

- The socket the `mielwm` and `aerospace` commands talk to.
- The files mielwm writes, including the status bar config it edits.
- Window pictures, window titles and anything else mielwm reads from other apps.
- How releases are signed.

Only the latest release gets fixes.
