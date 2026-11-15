# Zach's iTerm2 fork

Branch `zach` = our edits on top of upstream (gnachman/iTerm2). Commit edits here; only
committed work gets built.

## Edits

- Tab colors keep the same strength when the window is in the background
  (`ThirdParty/PSMTabBarControl/source/PSMMinimalTabStyle.m`).
- **App-docked panels** (`sources/AppDock/`, 2026-11-14): a profile with
  `"Dock To App Bundle ID"` becomes a panel that lives inside another app's window. Built
  for Claude inside World of Warcraft: the "Claude over WoW" profile
  (`zach/profiles/claude-over-wow.py` writes it to `DynamicProfiles/claude-over-wow.json`)
  takes ElvUI's right-chat slot, read from ElvUI's SavedVariables at launch and whenever the
  game rewrites them. Panel and text size follow the game window live (move, resize, other
  Spaces, fullscreen): one WoW UI unit = content height x UIScale / 768, so the panel is
  472 x (236 + 23) units at UIScale 0.63, 4 units in from the bottom-right corner, text 14.75
  units. Look per the approved comp: ElvUI flat panel (1 pt black edge, faint inner
  highlight, gold "Claude" tab header), violet text, gold accents, 60% backdrop, no title
  bar, shadow or rounded corners.
  - Hotkey (the profile's, Ctrl-Opt-Cmd-C): panel not focused = show it and give it the
    keyboard (WoW stays the active app; the panel is a non-activating panel). Panel focused
    = keyboard back to WoW, panel stays. Shift-Ctrl-Opt-Cmd-C = hide/show; the claude
    session keeps running while hidden. Clicking the panel focuses it, clicking the game
    focuses the game.
  - Visible only while WoW is frontmost or the panel has the keyboard; gone with WoW's
    window (created when it first appears; if claude exits, the next hotkey press or WoW
    window makes a new session). Never restored by window restoration.
  - Never tiled or moved by anything but its anchor: no title bar, not movable, refuses the
    Python API's set-frame, and any other move is undone. The window carries
    `user.appDocked`, which `~/Library/Application Support/iTerm2/Scripts/AutoLaunch/auto_tile.py`
    skips (backup of the old script: `Scripts/auto_tile.py.bak-20261114`).
  - Following WoW uses Accessibility notifications (the fork has the grant) plus display-rate
    sampling while the window changes; without the grant it polls the window list. Calls
    into WoW run off the main thread with a 0.2 s timeout, so a loading screen can't stall
    iTerm2.
  - Profile keys are listed at the top of `sources/AppDock/iTermAppDockSettings.swift`.
    Upstream files touched (one-line hooks, all marked "Zach's fork"): PseudoTerminal.h/.m,
    PseudoTerminal+WindowStyle.m, iTermApplicationDelegate.m, iTermAPIHelper.m,
    iTermHotKeyProfileBindingController.m, the SharedARC bridging header.
- **True Color Remap** (profile key `"True Color Remap": {"#d77757": "#f3cd5a", ...}`): 24-bit
  foreground colors a program sets are swapped for the profile's. The WoW panel turns Claude
  Code's orange into gold and its white into violet without touching Claude Code's theme.
  Touches VT100Terminal, VT100ScreenConfiguration, VT100ScreenMutableState, PTYSession.
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
