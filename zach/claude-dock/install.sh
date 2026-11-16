#!/bin/zsh
# Finish setting up Claude Dock once it is in /Applications (zach/update.sh makes it from each fork
# build, swap-on-quit installs it). Idempotent; never launches Claude Dock.
#   zach/claude-dock/install.sh
#
# 1. Seeds Claude Dock's settings from the main iTerm2's (seed-prefs.py; only when it has none).
# 2. Writes the "Claude over WoW" panel profile into Claude Dock's own DynamicProfiles folder.
# 3. Takes that profile out of the main iTerm2 (moved to ~/Documents/iTerm2-builds/ as a backup):
#    the main iTerm2 drops it within a second and frees Ctrl-Opt-Cmd-C for Claude Dock.
# 4. Installs the Hammerspoon launcher (hammerspoon/claude-dock.lua): Ctrl-Opt-Cmd-C starts
#    Claude Dock when it is not running. Loaded into the running Hammerspoon in place, never a
#    reload (a reload restarts every module and flashes their alerts).
set -euo pipefail

HERE=${0:A:h}
source "$HERE/claude-dock.conf"
TEAM=76Q7685NR2
PB=/usr/libexec/PlistBuddy
HS_BIN=/opt/homebrew/bin/hs
HS_DIR=$HOME/.hammerspoon
MAIN_DYNAMIC=$HOME/Library/Application\ Support/iTerm2/DynamicProfiles
BACKUPS=$HOME/Documents/iTerm2-builds

say() { print "claude-dock install: $*"; }
die() { print -u2 "claude-dock install: $*"; exit 1; }

# 0. The installed app must be the re-branded fork build, isolated under its own suite.
[ -d "$INSTALLED_APP" ] || die "$INSTALLED_APP is not installed yet (zach/update.sh stages it, swap-on-quit installs it)"
[ "$($PB -c 'Print :CFBundleIdentifier' "$INSTALLED_APP/Contents/Info.plist")" = "$BUNDLE_ID" ] \
    || die "$INSTALLED_APP does not have bundle id $BUNDLE_ID"
[ "$($PB -c 'Print :ZachForkSettingsSuite' "$INSTALLED_APP/Contents/Info.plist" 2>/dev/null)" = "$SUITE" ] \
    || die "$INSTALLED_APP does not name the $SUITE settings suite"
grep -q -a ZachForkSettingsSuite "$INSTALLED_APP/Contents/MacOS/$EXECUTABLE" \
    || die "$INSTALLED_APP predates the settings-suite hook; it would share the main iTerm2's settings"
codesign --verify --deep --strict "$INSTALLED_APP" || die "$INSTALLED_APP fails codesign --verify --deep --strict"
[ "$(codesign -dv "$INSTALLED_APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "$TEAM" ] \
    || die "$INSTALLED_APP is not signed by team $TEAM"
say "app ok: $INSTALLED_APP ($($PB -c 'Print :ZachForkBuildID' "$INSTALLED_APP/Contents/Info.plist" 2>/dev/null || echo 'no build id'))"

# 1. Settings.
python3 "$HERE/seed-prefs.py"

# 2. The panel profile, in Claude Dock's folder.
python3 "$HERE/../profiles/claude-over-wow.py"

# 3. Out of the main iTerm2.
if [ -f "$MAIN_DYNAMIC/claude-over-wow.json" ]; then
    mkdir -p "$BACKUPS"
    backup=$BACKUPS/claude-over-wow.main-iterm2-$(date +%Y%m%d-%H%M%S).json
    mv "$MAIN_DYNAMIC/claude-over-wow.json" "$backup"
    say "moved the main iTerm2's copy of the panel profile to $backup"
else
    say "the main iTerm2 has no panel profile (already moved)"
fi

# 4. Hammerspoon launcher.
if [ ! -d "$HS_DIR" ]; then
    say "no ~/.hammerspoon; skipping the launcher (Ctrl-Opt-Cmd-C works once Claude Dock is running)"
    exit 0
fi
hs_changed=0
if ! cmp -s "$HERE/hammerspoon/claude-dock.lua" "$HS_DIR/claude-dock.lua"; then
    cp "$HERE/hammerspoon/claude-dock.lua" "$HS_DIR/claude-dock.lua.new"
    mv -f "$HS_DIR/claude-dock.lua.new" "$HS_DIR/claude-dock.lua"
    hs_changed=1
fi
if ! grep -q 'require, "claude-dock"' "$HS_DIR/init.lua" 2>/dev/null; then
    hs_changed=1
    cat >> "$HS_DIR/init.lua" <<'LUA'

-- claude-dock: Ctrl-Opt-Cmd-C starts Claude Dock (the Claude panel inside WoW) when it is not
-- running; while it runs the key is Claude Dock's own. Source: ~/Documents/iTerm2/zach/claude-dock
-- (install.sh copies it here).
local okClaudeDock, claudeDock = pcall(require, "claude-dock")
if okClaudeDock then
  claudeDock.start()
else
  dbg("claude-dock FAILED: " .. tostring(claudeDock))
end
LUA
fi

# Load just this module into the running Hammerspoon and read its self-test from a marker file
# (hs -c's reply can be lost when run outside a terminal; a retry would load it twice).
state=$HOME/.local/state/claude-dock
mkdir -p "$state"
marker=$state/.hs-loaded
hs_load() {   # $1 = lua that leaves the module started; writes "<nonce> <selftest>" to the marker
    local nonce="$(date +%s)-$$-$RANDOM"
    rm -f "${marker:?}"
    local lua="$1
local f = io.open('$marker', 'w')
f:write('$nonce ' .. result)
f:close()"
    [ -x "$HS_BIN" ] && /usr/bin/perl -e 'alarm 25; exec @ARGV' "$HS_BIN" -t 20 -c "$lua" >/dev/null 2>&1 || true
    local got=""
    for _ in {1..80}; do   # 20 s: a busy Mac (load 60+) answers late
        got=$(cat "$marker" 2>/dev/null || true)
        [[ $got == "$nonce "* ]] && break
        sleep 0.25
    done
    [[ $got == "$nonce "* ]] && print -r -- "${got#$nonce }"
}
if (( hs_changed )); then
    result=$(hs_load "local m = package.loaded['claude-dock']
if m and m.stop then pcall(m.stop) end
package.loaded['claude-dock'] = nil
local ok, mod = pcall(require, 'claude-dock')
local result
if ok then
  local okStart, err = pcall(mod.start)
  result = okStart and ('started ' .. mod.selftest()) or ('FAILED ' .. tostring(err))
else
  result = 'FAILED ' .. tostring(mod)
end") || true
else
    result=$(hs_load "local m = package.loaded['claude-dock']
local result = m and ('loaded ' .. m.selftest()) or 'FAILED not loaded'") || true
fi
# The main iTerm2 lets go of Ctrl-Opt-Cmd-C a moment after step 3; the module retries every 30 s
# on its own, and once here so the result below is the real state.
if [[ $result == *"launcher-key=off"* && $result == *"running=false"* ]]; then
    sleep 3
    result=$(hs_load "local m = package.loaded['claude-dock']
local result = 'FAILED not loaded'
if m then m.stop(); m.start(); result = 'restarted ' .. m.selftest() end") || true
fi
case $result in
    *"launcher-key=on"*|*"running=true"*) say "hammerspoon launcher: $result" ;;
    "") die "hammerspoon did not answer; reload Hammerspoon from its menu when convenient (the launcher loads with it)" ;;
    *) die "hammerspoon launcher: $result" ;;
esac
say "done. Claude Dock has not been launched; Zach opens it the first time (zach/README.md, \"Claude Dock\")."
