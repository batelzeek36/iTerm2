#!/bin/zsh
# Build a signed Deployment iTerm2 from a source tree.
#   zach/build.sh <source-tree> <output-dir>
# Produces <output-dir>/build/Deployment/iTerm2.app signed with Zach's Developer ID, so Santa
# allows it by Team ID. The source tree is changed only in files git ignores or restores below.
set -euo pipefail

SRC=${1:?usage: build.sh <source-tree> <output-dir>}
OUT=${2:?usage: build.sh <source-tree> <output-dir>}
TEAM=76Q7685NR2
IDENTITY="Developer ID Application: ZACHARY GERALD BATES ($TEAM)"
DISABLED_FEED="http://127.0.0.1:9/zach-fork-nightly-updates-disabled.xml"

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$SRC"
mkdir -p "$OUT"

# Info.plist: the nightly plist keeps nightly-only features on (iTerm2 reads "nightly" in the
# testing feed URL). Every update feed points at a dead local address, so Sparkle can never
# install a stock build over the fork. Our own updater (zach/update.sh) replaces it.
cp plists/nightly-iTerm2.plist plists/iTerm2.plist
for key in SUFeedURL SUFeedURLForFinal SUFeedURLForTesting; do
    /usr/libexec/PlistBuddy -c "Set :$key $DISABLED_FEED" plists/iTerm2.plist
done

# Entitlements: keychain-access-groups needs George Nachman's provisioning profile, which no
# other team can use. Without it iTerm2 uses the login keychain, as development builds do.
# The file is restored from git after the build.
restore_entitlements() { git checkout -- iTerm2.entitlements 2>/dev/null || true; }
trap restore_entitlements EXIT
if /usr/libexec/PlistBuddy -c "Print :keychain-access-groups" iTerm2.entitlements >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" iTerm2.entitlements
fi

# Same as the Makefile's ingest-catalogs step.
cp -f xcstrings/Localizable.xcstrings sources/Localizable.xcstrings

xcodebuild -scheme iTerm2 -configuration Deployment -destination 'platform=macOS' \
    -skipPackagePluginValidation \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    SYMROOT="$OUT/build" OBJROOT="$OUT/obj" ENABLE_ADDRESS_SANITIZER=NO

APP="$OUT/build/Deployment/iTerm2.app"
codesign --verify --deep --strict "$APP"
team=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$team" = "$TEAM" ] || { echo "build.sh: signed by team '$team', expected $TEAM" >&2; exit 1; }
if command -v santactl >/dev/null; then
    santactl fileinfo "$APP" | grep -E "Rule|Decision" || true
fi
echo "build.sh: built $APP ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"))"
