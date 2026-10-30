#!/bin/bash
# Builds mielwm.app (release) into build/.
#
#   scripts/build-app.sh [--install] [--dmg]
#
#   --install  copy it to ~/Applications
#   --dmg      also make build/mielwm-<version>.dmg (signed, not notarized)
#
# Open at login is a switch in Settings > General.
#
# For CI (see .github/workflows/release.yml):
#   MIELWM_VERSION            the version, default 0.1.0
#   MIELWM_KEYCHAIN           a keychain that already holds the identity, and
#   MIELWM_KEYCHAIN_PASSWORD  its password: no login keychain is touched
#   MIELWM_REQUIRE_IDENTITY=1 never create an identity, never sign ad hoc
#   MIELWM_EXPECT_CERT_SHA1   the identity's leaf certificate SHA-1; any other fails
#
# Signing: macOS ties the Accessibility and Screen Recording grants to the
# app's signature. An ad-hoc signature changes with every build, so every
# rebuild would need the grants again. The script therefore creates a
# self-signed "mielwm Dev" code-signing identity once, in its own keychain
# (~/Library/Keychains/mielwm-dev.keychain-db, it only holds this key),
# and signs with it. That keychain's password is random, made on the first run
# and kept in your login keychain (service my.miel.mielwm.signing-keychain).
# Nothing here asks for your password; if signing with it fails, the app is signed ad hoc and the script
# says what to do.
set -euo pipefail

cd "$(dirname "$0")/.."
INSTALL=0 DMG=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --dmg) DMG=1 ;;
        *) echo "usage: $0 [--install] [--dmg]" >&2; exit 2 ;;
    esac
done

BUNDLE_ID=my.miel.mielwm
IDENTITY="mielwm Dev"
KEYCHAIN="${MIELWM_KEYCHAIN:-$HOME/Library/Keychains/mielwm-dev.keychain-db}"
PASSWORD_SERVICE=my.miel.mielwm.signing-keychain
VERSION=${MIELWM_VERSION:-0.1.0}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP=build/mielwm.app

echo "== swift build -c release"
# SwiftPM's build system records the deployment target as the SDK version. macOS
# 26 and later then draw the app in its old look, without the glass sidebar.
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
# The oldest macOS, from Package.swift's .macOS(.vNN).
MIN_MACOS=$(sed -n 's/.*\.macOS(\.v\([0-9]*\)).*/\1/p' Package.swift).0
# A miss would link minos 0.0 and ship an app that claims to run on any macOS.
[[ $MIN_MACOS =~ ^[0-9]+\.0$ ]] || { echo "can't read the macOS version from Package.swift" >&2; exit 1; }
STAMP=(-Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION")
# Short output, but a failed build stops here: never sign and ship the last good binary.
for product in mielwm mielwm-aerospace; do
    if ! build_log=$(swift build -c release --product $product "${STAMP[@]}" 2>&1); then
        echo "$build_log" | grep -E "error" || echo "$build_log" | tail -20
        echo "build failed" >&2
        exit 1
    fi
    echo "$build_log" | grep -E "error|Build complete" || true
done
BIN_DIR=$(swift build -c release --show-bin-path "${STAMP[@]}")
BIN=$BIN_DIR/mielwm
[ -x "$BIN" ] && [ -x "$BIN_DIR/mielwm-aerospace" ] || { echo "build failed" >&2; exit 1; }

echo "== $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mielwm"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png LICENSE NOTICE "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>mielwm</string>
    <key>CFBundleDisplayName</key><string>mielwm</string>
    <key>CFBundleExecutable</key><string>mielwm</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>mielwm moves and focuses your windows on the canvas and listens for its keyboard shortcuts.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>mielwm shows live pictures of your windows on the zoomed-out canvas.</string>
</dict>
</plist>
EOF

# Barik (docs/aerospace.md): its `aerospace` command, and the hidden app called
# AeroSpace it looks for. One binary does both.
HELPER="$APP/Contents/Helpers/AeroSpace.app"
mkdir -p "$HELPER/Contents/MacOS"
cp "$BIN_DIR/mielwm-aerospace" "$APP/Contents/Helpers/aerospace"
cp "$BIN_DIR/mielwm-aerospace" "$HELPER/Contents/MacOS/AeroSpace"
cat > "$HELPER/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID.aerospace-helper</string>
    <key>CFBundleName</key><string>AeroSpace</string>
    <key>CFBundleExecutable</key><string>AeroSpace</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# The identity, made once. -T lets codesign use the key; the partition list
# (set with the keychain's own known password) stops the "allow access" dialog.
make_identity() {
    local tmp
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    # /usr/bin/openssl is LibreSSL, whose PKCS#12 the security tool reads.
    /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$IDENTITY" \
        -passout pass:mielwm -out "$tmp/id.p12" 2>/dev/null
    if [ ! -f "$KEYCHAIN" ]; then
        local search
        search=$(security list-keychains -d user | tr -d '"')
        security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
        security list-keychains -d user -s $search # keep your keychain search list as it was
    fi
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN" # no auto-lock
    security import "$tmp/id.p12" -k "$KEYCHAIN" -P mielwm -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
}

echo "== signing"
SIGNED=adhoc
# Inside out, all with the same signature: the command, the helper, then mielwm.app.
sign_all() {
    codesign --force "$@" -i "$BUNDLE_ID.aerospace" "$APP/Contents/Helpers/aerospace" &&
        codesign --force "$@" "$HELPER" &&
        codesign --force "$@" -i "$BUNDLE_ID" "$APP"
}
# A fixed password would let any program sign as "mielwm Dev" and inherit
# the app's permission grants, so it is random and lives in the login keychain.
REQUIRE=${MIELWM_REQUIRE_IDENTITY:-0}
fail() { echo "signing: $*" >&2; exit 1; }
if [ -n "${MIELWM_KEYCHAIN_PASSWORD:-}" ]; then
    KEYCHAIN_PASSWORD=$MIELWM_KEYCHAIN_PASSWORD
else
    KEYCHAIN_PASSWORD=$(security find-generic-password -s "$PASSWORD_SERVICE" -a "$USER" -w 2>/dev/null || true)
fi
if [ -z "$KEYCHAIN_PASSWORD" ]; then
    [ "$REQUIRE" = 1 ] && fail "no keychain password"

    KEYCHAIN_PASSWORD=$(/usr/bin/openssl rand -hex 24)
    security add-generic-password -U -s "$PASSWORD_SERVICE" -a "$USER" -w "$KEYCHAIN_PASSWORD" -T /usr/bin/security
    [ -f "$KEYCHAIN" ] && security delete-keychain "$KEYCHAIN" # its password is lost: make the identity again
fi
if [ ! -f "$KEYCHAIN" ] || ! security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    [ "$REQUIRE" = 1 ] && fail "no \"$IDENTITY\" identity in $KEYCHAIN"
    echo "creating the \"$IDENTITY\" identity in $KEYCHAIN"
    make_identity || echo "could not create the identity"
fi
if [ -f "$KEYCHAIN" ]; then
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" 2>/dev/null || true
    sign_log=$(mktemp)
    # By hash when it is known: codesign may pass over an untrusted self-signed identity looked up by name.
    if sign_all --timestamp=none --keychain "$KEYCHAIN" -s "${MIELWM_EXPECT_CERT_SHA1:-$IDENTITY}" 2>"$sign_log"; then
        SIGNED=identity
    else
        echo "signing with \"$IDENTITY\" failed:"; sed 's/^/  /' "$sign_log"
    fi
    rm -f "$sign_log"
fi
if [ "$SIGNED" = adhoc ]; then
    [ "$REQUIRE" = 1 ] && fail "could not sign with \"$IDENTITY\""
    sign_all -s -
    echo "signed ad hoc: macOS will ask for Accessibility and Screen Recording again after each rebuild."
    echo "If the identity is the problem, trusting it once (asks for your password) usually fixes it:"
    echo "  security find-certificate -c \"$IDENTITY\" -p \"$KEYCHAIN\" > /tmp/mielwm-dev.pem"
    echo "  sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain /tmp/mielwm-dev.pem"
fi
codesign --verify --deep --strict "$APP" || fail "the signature does not verify"
REQUIREMENT=$(codesign -dr - "$APP" 2>&1 | grep designated | sed 's/^# //')
echo "signed ($SIGNED): $REQUIREMENT"
if [ -n "${MIELWM_EXPECT_CERT_SHA1:-}" ]; then
    # Another certificate would make every user grant Accessibility and Screen Recording again.
    echo "$REQUIREMENT" | grep -qi "H\"$MIELWM_EXPECT_CERT_SHA1\"" || fail "signed by an unexpected certificate"
fi

# Quits a running app the clean way (both take SIGTERM as Quit and put their
# windows back on screen first); true if it was running.
quit_app() {
    pgrep -qf "$2" || return 1
    echo "quitting $1"
    pkill -TERM -f "$2" || true
    for _ in $(seq 1 40); do pgrep -qf "$2" || return 0; sleep 0.5; done
    echo "$1 did not quit; quit it from its menu, then run this again" >&2
    exit 1
}
if [ $INSTALL = 1 ]; then
    echo "== ~/Applications/mielwm.app"
    mkdir -p "$HOME/Applications"
    REOPEN=0 # running before, running again after
    quit_app mielwm "mielwm.app/Contents/MacOS/mielwm$" && REOPEN=1
    rm -rf "$HOME/Applications/mielwm.app"
    cp -R "$APP" "$HOME/Applications/"
    if [ $REOPEN = 1 ]; then open "$HOME/Applications/mielwm.app"; fi
fi
if [ $DMG = 1 ]; then
    DMG_PATH="build/mielwm-$VERSION.dmg"
    echo "== $DMG_PATH"
    stage=$(mktemp -d)
    cp -R "$APP" "$stage/"
    cp LICENSE NOTICE "$stage/"
    ln -s /Applications "$stage/Applications"
    rm -f "$DMG_PATH"
    hdiutil create -quiet -volname "mielwm $VERSION" -srcfolder "$stage" -fs HFS+ -format UDZO "$DMG_PATH"
    rm -rf "$stage"
fi
echo "done: $APP"
