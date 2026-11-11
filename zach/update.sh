#!/bin/zsh
# Nightly fork update (LaunchAgent com.zach.iterm2-fork-update, 04:00).
#
# 1. Fetch upstream (gnachman/iTerm2) and find the newest vYYYYMMDD-nightly tag.
# 2. In a throwaway worktree, check out that tag and merge our `zach` branch into it.
#    The `zach` branch itself is never rewritten, so our edits are never lost. On a merge
#    conflict: abort, keep the current build, notify Zach.
# 3. Build it signed (zach/build.sh) and stage it. zach/swap-on-quit installs the staged
#    build the next time iTerm2 quits.
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

notify() {
    echo "NOTIFY: $1"
    [ -x "$PING" ] && "$PING" --mac "iTerm2 fork: $1" || true
}

cd "$REPO"
git fetch --quiet upstream --tags --filter=blob:none
git fetch --quiet origin
tag=$(git tag -l 'v*-nightly' --sort=-creatordate | head -1)
[ -n "$tag" ] || { notify "no upstream nightly tag found"; exit 1; }
ours=$(git rev-parse zach)
build_id="$tag+$(git rev-parse --short "$ours")"
echo "newest nightly: $tag, zach: $(git rev-parse --short "$ours")"

if [ "${1:-}" != "--force" ] && [ -f "$STATE" ] && [ "$(cat "$STATE")" = "$build_id" ]; then
    echo "already built $build_id; nothing to do"
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
git submodule update --init --recursive --quiet

# Native dependencies (OpenSSL, libsixel, libgit2, Sparkle, ...) are rebuilt, in upstream's
# sandbox, whenever the Xcode version or any submodule changes.
deps_key="$(xcodebuild -version | tr '\n' ' ')|$(git submodule status --recursive | shasum | cut -c1-16)"
if [ ! -f "$BUILDS/deps-key" ] || [ "$(cat "$BUILDS/deps-key")" != "$deps_key" ]; then
    echo "building native dependencies"
    taskpolicy -b make -j"$(sysctl -n hw.ncpu)" paranoid-deps BUILD_DIR="$BUILDS/out/build"
    echo "$deps_key" > "$BUILDS/deps-key"
fi

if ! taskpolicy -b "$WT/zach/build.sh" "$WT" "$BUILDS/out"; then
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

# Refresh the installed copies of the fork tooling from the tree that was just built.
"$WT/zach/install.sh" --tools-only

# Keep the GitHub fork current (fast-forward pushes only; never forced).
git -C "$REPO" push --quiet origin "refs/remotes/upstream/master:refs/heads/master" || echo "fork master push skipped"
git -C "$REPO" push --quiet origin zach || echo "zach push skipped"
echo "== $(date) done"
