#!/bin/zsh
# Install the fork tooling: the swap helper, the update script and their LaunchAgents.
#   zach/install.sh               build + install everything, (re)load both LaunchAgents
#   zach/install.sh --tools-only  rebuild the helper and copy the scripts (update.sh calls this)
set -euo pipefail

HERE=${0:A:h}
BUILDS=$HOME/Documents/iTerm2-builds
BIN=$BUILDS/bin
AGENTS=$HOME/Library/LaunchAgents
IDENTITY=EA410B8C8FB4CA6A7AFF792C68185BE45719C056   # Developer ID Application: ZACHARY GERALD BATES (76Q7685NR2)
GUI=gui/$(id -u)
mkdir -p "$BIN" "$BUILDS/logs"

# Helper, signed with Zach's team so Santa allows it and macOS lets it replace the fork app
# (same team) without an App Management prompt.
swiftc -O "$HERE/swap-on-quit/main.swift" -o "$BIN/swap-on-quit.new"
codesign --force --options runtime --identifier com.zach.iterm2-fork-swap --sign "$IDENTITY" "$BIN/swap-on-quit.new"
mv -f "$BIN/swap-on-quit.new" "$BIN/swap-on-quit"

# Replace scripts by rename, never in place: update.sh may be the script running right now.
cp "$HERE/update.sh" "$BIN/update.sh.new"
chmod 755 "$BIN/update.sh.new"
mv -f "$BIN/update.sh.new" "$BIN/update.sh"

if [ "${1:-}" = "--tools-only" ]; then
    # Restart the helper on its new binary if it is loaded.
    launchctl kickstart -k "$GUI/com.zach.iterm2-fork-swap" 2>/dev/null || true
    echo "install.sh: tools refreshed"
    exit 0
fi

for label in com.zach.iterm2-fork-swap com.zach.iterm2-fork-update; do
    sed "s|__HOME__|$HOME|g" "$HERE/launchd/$label.plist" > "$AGENTS/$label.plist"
    plutil -lint "$AGENTS/$label.plist" >/dev/null
    launchctl bootout "$GUI/$label" 2>/dev/null || true
    launchctl bootstrap "$GUI" "$AGENTS/$label.plist"
done
echo "install.sh: helper and LaunchAgents installed"
