#!/bin/zsh
# Make "Claude Dock.app" from a signed fork build of iTerm2: the same binaries, its own identity.
#   zach/claude-dock/rebrand.sh <iTerm2.app> <output-dir> --build-id <id>   stage <output-dir>/Claude Dock.app + BUILD_ID
#   zach/claude-dock/rebrand.sh <iTerm2.app> <output-dir> --proof          a check of the steps on a build that
#                                                                          predates the suite hook; never install it
#
# What changes (zach/README.md, "Claude Dock"):
#   - Info.plist: bundle id com.zakkbates.claudedock, name "Claude Dock", executable ClaudeDock,
#     ZachForkSettingsSuite = ClaudeDock (main.m isolates every launch under that suite: its own
#     defaults, private defaults, Application Support, ~/.config folder and sockets), Sparkle's
#     automatic checks off. No URL schemes, document types or Services: Claude Dock never takes
#     ssh:, folders, scripts or iTerm2 files from the main iTerm2.
#   - Icon: its own (icon/ClaudeDock.icns, drawn from icon/claude-dock-icon.svg by
#     icon/make-icns.py): CFBundleIconFile = ClaudeDock, and CFBundleIconName (iTerm2's icon in
#     Assets.car, which macOS would prefer) removed.
#   - Entitlements: the app group named for the main iTerm2 is dropped (nothing uses it).
#   - Signature: the outer app is re-signed with Zach's Developer ID, hardened runtime, as
#     zach/build.sh signs the build. Nested code (frameworks, XPC services, helpers, Sparkle) keeps
#     the signatures Xcode gave it; the XPC services keep their ids because the app connects to
#     them by name, and they run inside Claude Dock's own launchd domain.
set -euo pipefail

HERE=${0:A:h}
source "$HERE/claude-dock.conf"
IDENTITY=EA410B8C8FB4CA6A7AFF792C68185BE45719C056   # Developer ID Application: ZACHARY GERALD BATES (76Q7685NR2)
TEAM=76Q7685NR2
PB=/usr/libexec/PlistBuddy

usage() { echo "usage: rebrand.sh <iTerm2.app> <output-dir> (--build-id <id> | --proof)" >&2; exit 64; }
SRC=${1:-}; OUT_DIR=${2:-}
[ -n "$SRC" ] && [ -n "$OUT_DIR" ] || usage
shift 2
BUILD_ID=""; PROOF=0
while [ $# -gt 0 ]; do
    case $1 in
        --build-id) BUILD_ID=${2:-}; [ -n "$BUILD_ID" ] || usage; shift 2 ;;
        --proof) PROOF=1; shift ;;
        *) usage ;;
    esac
done
[ $PROOF = 1 ] || [ -n "$BUILD_ID" ] || usage

say() { echo "rebrand: $*"; }
die() { echo "rebrand: $*" >&2; exit "${2:-1}"; }

# The source must be a verified fork build signed by Zach's team.
[ -f "$SRC/Contents/Info.plist" ] && [ -x "$SRC/Contents/MacOS/iTerm2" ] || die "$SRC is not an iTerm2 build"
codesign --verify --deep --strict "$SRC" || die "$SRC does not pass codesign --verify --deep --strict"
src_team=$(codesign -dv "$SRC" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$src_team" = "$TEAM" ] || die "$SRC is signed by team '$src_team', expected $TEAM"

# Without the suite hook (main.m, ZachForkSettingsSuite) a re-branded copy would share
# ~/.config/iterm2, com.googlecode.iterm2.private and the iterm2: handler with the main iTerm2.
if ! grep -q -a ZachForkSettingsSuite "$SRC/Contents/MacOS/iTerm2"; then
    [ $PROOF = 1 ] || die "this build predates the Claude Dock suite hook (zach/claude-dock, main.m); not staging it" 3
    say "proof run: this build has no suite hook, so the result must never be installed or opened"
fi

mkdir -p "$OUT_DIR"
NEW=$OUT_DIR/.incoming-$$
rm -rf "${NEW:?}"
mkdir -p "$NEW"
trap 'rm -rf "${NEW:?}"' EXIT
APP=$NEW/$APP_NAME.app
ditto "$SRC" "$APP"
PLIST=$APP/Contents/Info.plist

# Main executable: its own name, so nothing that looks for iTerm2 by process name finds it.
mv "$APP/Contents/MacOS/iTerm2" "$APP/Contents/MacOS/$EXECUTABLE"

# Its own icon, before signing (resources are sealed by the signature).
ICON=$HERE/icon/ClaudeDock.icns
[ -s "$ICON" ] || die "missing $ICON (zach/claude-dock/icon/make-icns.py makes it)"
cp "$ICON" "$APP/Contents/Resources/ClaudeDock.icns"

plist_set() {   # key type value: set, or add when missing
    $PB -c "Set :$1 $3" "$PLIST" 2>/dev/null || $PB -c "Add :$1 $2 $3" "$PLIST"
}
plist_delete() { $PB -c "Delete :$1" "$PLIST" 2>/dev/null || true; }
plist_set CFBundleIdentifier string "$BUNDLE_ID"
plist_set CFBundleName string "$APP_NAME"
plist_set CFBundleDisplayName string "$APP_NAME"
plist_set CFBundleExecutable string "$EXECUTABLE"
plist_set ZachForkSettingsSuite string "$SUITE"
plist_set CFBundleIconFile string ClaudeDock
plist_delete CFBundleIconName
plist_set SUEnableAutomaticChecks bool false
plist_set SUAutomaticallyUpdate bool false
plist_set SUAllowsAutomaticUpdates bool false
for key in CFBundleURLTypes CFBundleDocumentTypes NSServices UTExportedTypeDeclarations UTImportedTypeDeclarations; do
    plist_delete $key
done
if [ -n "$BUILD_ID" ]; then
    plist_set ZachForkBuildID string "$BUILD_ID"
fi
plutil -lint "$PLIST" >/dev/null

# Entitlements of the build, minus the app group named for the main iTerm2.
ENT=$NEW/entitlements.plist
codesign -d --entitlements - --xml "$SRC" > "$ENT" 2>/dev/null
plutil -lint "$ENT" >/dev/null
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$ENT" 2>/dev/null || true

sign() {
    codesign --force --options runtime "$@" --entitlements "$ENT" --identifier "$BUNDLE_ID" \
        --sign "$IDENTITY" "$APP"
}
# A secure timestamp needs Apple's timestamp server; without the network the signature is still
# valid for a local, unquarantined app.
if ! sign --timestamp 2>"$NEW/sign.err"; then
    cat "$NEW/sign.err" >&2
    say "signing with a secure timestamp failed; signing without one"
    sign --timestamp=none
fi

codesign --verify --deep --strict --verbose=2 "$APP"
info=$(codesign -dv "$APP" 2>&1)
[ "$(sed -n 's/^Identifier=//p' <<<"$info")" = "$BUNDLE_ID" ] || die "signed identifier is not $BUNDLE_ID"
[ "$(sed -n 's/^TeamIdentifier=//p' <<<"$info")" = "$TEAM" ] || die "signed team is not $TEAM"
grep -q "flags=.*runtime" <<<"$info" || die "hardened runtime flag missing"
[ "$($PB -c 'Print :CFBundleIdentifier' "$PLIST")" = "$BUNDLE_ID" ] || die "Info.plist bundle id was not set"
[ "$($PB -c 'Print :CFBundleIconFile' "$PLIST")" = ClaudeDock ] && [ -s "$APP/Contents/Resources/ClaudeDock.icns" ] \
    && ! $PB -c 'Print :CFBundleIconName' "$PLIST" >/dev/null 2>&1 || die "the icon was not set"
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q application-groups; then
    die "the app group entitlement is still present"
fi
say "signed: $(grep -E '^(Identifier|TeamIdentifier|Timestamp|Signed Time)=' <<<"$info" | tr '\n' ' ')"
# Gatekeeper's view. A locally built app is never quarantined, so Gatekeeper does not assess it
# at launch; an unnotarized Developer ID build reads "rejected" here, the same as the fork's iTerm2.
say "spctl: $(spctl --assess --type execute -vv "$APP" 2>&1 | tr '\n' ' ')"
if command -v santactl >/dev/null; then
    say "santa: $(santactl fileinfo "$APP" 2>/dev/null | grep -E '^(Rule|Expected Decision|Team ID|Signing ID)' | tr -s ' ' | tr '\n' ';')"
fi

# Into place: replace the previous staged copy by rename.
DEST=$OUT_DIR/$APP_NAME.app
rm -rf "${DEST:?}"
mv "$APP" "$DEST"
if [ -n "$BUILD_ID" ]; then
    echo "$BUILD_ID" > "$OUT_DIR/BUILD_ID.new"
    mv -f "$OUT_DIR/BUILD_ID.new" "$OUT_DIR/BUILD_ID"
fi
say "ready: $DEST${BUILD_ID:+ ($BUILD_ID)}"
