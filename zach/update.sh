#!/bin/zsh
# Nightly fork update (LaunchAgent com.zach.iterm2-fork-update, 04:00 and at load, started by
# zach/run-update so it can read ~/Documents).
#
# 1. Fetch upstream (gnachman/iTerm2) and find the newest vYYYYMMDD-nightly tag.
# 2. In a throwaway worktree, check out that tag and merge our `zach` branch into it.
#    The `zach` branch itself is never rewritten, so our edits are never lost. On a merge
#    conflict: abort, keep the current build, notify Zach.
# 3. Build it signed (zach/build.sh) and stage it. zach/swap-on-quit installs the staged
#    build the next time iTerm2 quits.
# 4. (Retired 2026-11-17) Claude Dock is no longer made from fork builds: it is its own app,
#    ~/Developer/claude-dock.
#
# Only committed work on `zach` is built. Runs at background priority.
#   zach/update.sh [--force]   --force rebuilds even when nothing changed.
set -euo pipefail

REPO=$HOME/Documents/iTerm2
BUILDS=$HOME/Documents/iTerm2-builds
WT=$BUILDS/worktree
LOG_DIR=$BUILDS/logs
STATE=$BUILDS/last-built
PING=$HOME/.claude/skills/work-on/bin/ping-zach
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$LOG_DIR" "$BUILDS/staged"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG=$LOG_DIR/update-$STAMP.log
exec > >(tee -a "$LOG") 2>&1
echo "== $(date) fork update"

source "${0:A:h}/xcode.sh"

# During quiet hours (the 4 AM run; Zach lets this one build run then, 2026-11-15) a notice is a
# silent banner: ping-zach plays a sound, which would land in his ears over the fan at night.
# A flag whose text starts with "test" is quiet hours' sound-reset test, not a night.
quiet_hours_on() {
    local flag=$HOME/.claude/quiet-hours/active
    [[ -f $flag && "$(<$flag)" != test* ]]
}
notify() {
    echo "NOTIFY: $1"
    if quiet_hours_on; then
        local text=${1//[\"\\]/}
        osascript -e "display notification \"iTerm2 fork: ${text[1,180]}\" with title \"iTerm2 fork (quiet hours)\"" || true
        return 0
    fi
    [ -x "$PING" ] && "$PING" --mac "iTerm2 fork: $1" || true
}

# Santa (lockdown + transitive allowlisting) approves what Apple's linker writes, but a build
# tool can run a freshly linked binary (cargo build scripts) before the approval lands
# ("No transitive rule created before timeout"). A second attempt reuses the now-approved
# binaries, so every build step gets one retry.
retry() {
    "$@" && return 0
    echo "retrying after a failure (Santa may still have been approving new binaries): $*"
    "$@"
}

cd "$REPO"
git fetch --quiet upstream --tags --filter=blob:none
git fetch --quiet origin
# No `| head -1` here: under pipefail, head exiting early kills git with SIGPIPE, and at
# background priority that race fails most runs (11-12: 22 of 30, the job exited 141).
tag=$(git for-each-ref --count=1 --sort=-creatordate --format='%(refname:short)' 'refs/tags/v*-nightly')
[ -n "$tag" ] || { notify "no upstream nightly tag found"; exit 1; }
ours=$(git rev-parse zach)
build_id="$tag+$(git rev-parse --short "$ours")"
echo "newest nightly: $tag, zach: $(git rev-parse --short "$ours")"

# Claude Dock is its own app since 2026-11-17 (~/Developer/claude-dock, bundle.sh --install puts it in
# /Applications). Fork builds no longer make or stage it: a re-branded copy in staged-claude-dock/
# would be swapped over the real one by swap-on-quit the next time it quits or relaunches itself.
# zach/claude-dock/rebrand.sh stays in the tree, unused.
dock_has() { return 0; }
make_claude_dock() {
    echo "Claude Dock: made by ~/Developer/claude-dock now, not from fork builds"
    return 0
}

if [ "${1:-}" != "--force" ] && [ -f "$STATE" ] && [ "$(cat "$STATE")" = "$build_id" ]; then
    echo "already built $build_id; nothing to do for iTerm2"
    # Catch Claude Dock up when it missed this build (the first run with the hook, or a re-brand
    # that failed last time), from a verified copy of exactly this build.
    if ! dock_has "$build_id"; then
        src=""
        if [ "$(cat "$BUILDS/staged/BUILD_ID" 2>/dev/null)" = "$build_id" ] && [ -d "$BUILDS/staged/iTerm.app" ]; then
            src=$BUILDS/staged/iTerm.app
        elif [ "$(cat "$BUILDS/installed-BUILD_ID" 2>/dev/null)" = "$build_id" ]; then
            src=/Applications/iTerm.app
        fi
        if [ -n "$src" ] && [ -d "$WT" ]; then
            make_claude_dock "$src" "$WT" || exit 6
        else
            echo "Claude Dock: no copy of $build_id to make it from"
        fi
    fi
    exit 0
fi

# Fresh worktree at the upstream tag, then merge our branch on top.
if [ -d "$WT" ]; then
    git -C "$WT" merge --abort 2>/dev/null || true
    git -C "$WT" reset --quiet --hard
    git -C "$WT" checkout --quiet --detach "$tag"
else
    git worktree add --quiet --detach "$WT" "$tag"
fi
cd "$WT"
if ! git -c user.name="Zach Bates" -c user.email="batelzeek@gmail.com" \
        merge --no-edit --quiet zach -m "Merge zach edits onto $tag"; then
    git diff --name-only --diff-filter=U | sed 's/^/conflict: /'
    git merge --abort
    notify "our edits conflict with upstream $tag; still running the previous build (log: $LOG)"
    exit 2
fi
# Start from clean submodules before moving them: the previous build leaves outputs inside them
# (NMSSH's prebuilt libssl.a and friends), and a nightly that bumps such a submodule makes
# `submodule update` refuse to check it out (11-14 04:00: "Your local changes ... would be
# overwritten by checkout", the run died without a notification).
git submodule foreach --quiet --recursive 'git reset --quiet --hard && git clean --quiet -ffdx'
if ! git submodule update --init --recursive --quiet; then
    notify "submodule checkout for $tag failed; still running the previous build (log: $LOG)"
    exit 5
fi

# Native dependencies (OpenSSL, libsixel, libgit2, Sparkle, ...) are built in upstream's
# sandbox, the same as `make paranoid-deps` minus sfsymbolenum: that step regenerates
# ThirdParty/SFSymbolEnum from the SF Symbols app (a sudo .pkg install), and upstream commits
# its output, so the committed files are used as they are.
deps_targets=(${(z)$(sed -n 's/^deps: force //p' Makefile)})
deps_targets=(${deps_targets:#sfsymbolenum})
make_deps() {
    nice -n 10 /usr/bin/sandbox-exec -f deps.sb make -j"$(sysctl -n hw.ncpu)" \
        BUILD_DIR="$BUILDS/out/build" "${deps_targets[@]}"
}
# Rebuilt on every run: the worktree reset restores upstream's prebuilt copies (made with
# upstream's Xcode), and the Xcode project refuses to build unless last-xcode-version matches
# the Xcode in use.
echo "building native dependencies: ${deps_targets[*]}"
# Clean again after the checkout: a submodule that moved can leave files behind.
git submodule foreach --quiet --recursive 'git reset --quiet --hard && git clean --quiet -ffdx'
tools/check-submodule-cleanliness
# The retry reruns make in place, keeping binaries Santa has approved by now.
if ! retry make_deps; then
    notify "native dependencies failed to build; still running the previous build (log: $LOG)"
    exit 4
fi
xcodebuild -version > last-xcode-version
# Sparkle's nested helpers come out ad-hoc signed; sign them with Zach's Developer ID, as
# upstream's `make sparkle SIGNED=1` does with George's.
CODESIGN_IDENTITY="Developer ID Application: ZACHARY GERALD BATES (76Q7685NR2)" \
    tools/sign_sparkle_helpers.sh ThirdParty/Sparkle.framework

if ! retry nice -n 10 "$WT/zach/build.sh" "$WT" "$BUILDS/out"; then
    notify "build of $build_id failed; still running the previous build (log: $LOG)"
    exit 3
fi

# Stage atomically: copy next to the staged folder, then rename into place.
NEW=$BUILDS/staged/.incoming-$STAMP
rm -rf "${NEW:?}"
mkdir -p "$NEW"
ditto "$BUILDS/out/build/Deployment/iTerm2.app" "$NEW/iTerm.app"
codesign --verify --deep --strict "$NEW/iTerm.app"
rm -rf "${BUILDS:?}/staged/iTerm.app"
mv "$NEW/iTerm.app" "$BUILDS/staged/iTerm.app"
rmdir "$NEW"
echo "$build_id" > "$BUILDS/staged/BUILD_ID"
echo "$build_id" > "$STATE"
echo "staged $build_id; it installs the next time iTerm2 quits"

dock_ok=1
make_claude_dock "$BUILDS/out/build/Deployment/iTerm2.app" "$WT" || dock_ok=0

# Refresh the installed copies of the fork tooling from the tree that was just built.
"$WT/zach/install.sh" --tools-only

# Keep the GitHub fork current (fast-forward pushes only; never forced).
git -C "$REPO" push --quiet origin "refs/remotes/upstream/master:refs/heads/master" || echo "fork master push skipped"
git -C "$REPO" push --quiet origin zach || echo "zach push skipped"
echo "== $(date) done"
# iTerm2 is staged; only Claude Dock failed (already notified above).
(( dock_ok )) || exit 6
