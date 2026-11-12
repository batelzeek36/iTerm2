# Zach's iTerm2 fork

Branch `zach` = our edits on top of upstream (gnachman/iTerm2). Commit edits here; only
committed work gets built.

## Edits

- Tab colors keep the same strength when the window is in the background
  (`ThirdParty/PSMTabBarControl/source/PSMMinimalTabStyle.m`).
- Build-time only (zach/build.sh, never committed to upstream files): nightly channel plist
  (nightly-only features on), update feeds pointed at a dead local address so a stock build
  can never install over ours, `keychain-access-groups` dropped (it needs George Nachman's
  provisioning profile).

## How updates work

- `com.zach.iterm2-fork-update` (04:00 daily, and at load: login, `install.sh`, quiet hours'
  `wake`) runs `run-update`, which runs `update.sh`: fetch upstream, take the
  newest `v*-nightly` tag, merge `zach` onto it in `~/Documents/iTerm2-builds/worktree`,
  build signed with Zach's Developer ID (team 76Q7685NR2), stage it in
  `~/Documents/iTerm2-builds/staged/`. The `zach` branch is never rewritten. A merge
  conflict or a failed build leaves the running build alone and sends a Mac notification.
  Nothing new upstream = exits at once.
- Why `run-update` (11-12): a launchd job that starts `/bin/zsh` directly gets no access to
  `~/Documents`, so the 04:00 runs on 11-11 and 11-12 died with "can't open input file". The
  launcher is signed under its own identifier (`com.zach.iterm2-fork-update`), holds the
  Documents grant (asked for once), and `update.sh` inherits it. It also skips the run while
  quiet hours are on (no builds on the Mac at night); `wake` loads the job again, which
  catches up.
- `com.zach.iterm2-fork-swap` runs `swap-on-quit`: when a staged build is waiting and
  iTerm2 quits, it moves the build into `/Applications/iTerm.app` within milliseconds. The
  replaced app goes to `~/Documents/iTerm2-builds/previous/`.

## Commands

- Build now: `~/Documents/iTerm2-builds/bin/update.sh --force`
- State: `~/Documents/iTerm2-builds/bin/swap-on-quit --status`
- Run the nightly job now, as launchd does: `launchctl kickstart gui/$(id -u)/com.zach.iterm2-fork-update`
- Documents access of the launcher: `~/Documents/iTerm2-builds/bin/run-update --probe` (from a
  terminal this reports the terminal's access; the real test is a launchd run)
- Logs: `~/Documents/iTerm2-builds/logs/`
- Reinstall tooling: `zach/install.sh`

## Rollback

- Previous build: move `~/Documents/iTerm2-builds/previous/iTerm.app` back to
  `/Applications/iTerm.app` while iTerm2 is not running.
- Stock 3.7.2: `~/Documents/iTerm2-builds/iTerm-3.7.2.zip`.
- Stop the automation: `launchctl bootout gui/$(id -u)/com.zach.iterm2-fork-update` and
  the same for `com.zach.iterm2-fork-swap`.
