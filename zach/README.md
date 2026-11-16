# Zach's iTerm2 fork

Branch `zach` = our edits on top of upstream (gnachman/iTerm2). Commit edits here; only
committed work gets built.

## Edits

- Tab colors keep the same strength when the window is in the background
  (`ThirdParty/PSMTabBarControl/source/PSMMinimalTabStyle.m`).
- **App-docked panels** (`sources/AppDock/`, 2026-11-14): a profile with
  `"Dock To App Bundle ID"` becomes a panel that lives inside another app's window. Built
  for Claude inside World of Warcraft: the "Claude over WoW" profile
  (`zach/profiles/claude-over-wow.py` writes it to Claude Dock's
  `~/Library/Application Support/ClaudeDock/DynamicProfiles/claude-over-wow.json`; since
  2026-11-15 the panel runs in **Claude Dock**, below, never in the main iTerm2)
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
    session keeps running while hidden.
  - Clicks: until it has the keyboard the panel is click-through (the terminal window
    ignores mouse events and the edges are a separate click-ignoring window), so clicks and
    scrolls in its slot reach the game (a bag opened there) and never hand the keyboard to
    Claude. Only the header takes a click: it focuses the panel. Focused, the terminal takes
    its own clicks; clicking the game gives the keyboard back to the game.
  - ZachPaladin's `/zdock` (wow-forever-addons, dock.lua) empties the slot on the game's
    side: ElvUI's right chat hidden (its chat types join the main chat), its toggle parked,
    tooltips above the slot; `/zdock off` undoes it.
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
    PseudoTerminal+WindowStyle.m (also: a docked window is never a compact window, whose
    theme frame left a title bar's height of the panel empty), iTermApplicationDelegate.m, iTermAPIHelper.m,
    iTermHotKeyProfileBindingController.m, the SharedARC bridging header.
- **True Color Remap** (profile key `"True Color Remap": {"#d77757": "#f3cd5a", ...}`): 24-bit
  text and background colors a program sets are swapped for the profile's. The WoW panel
  turns Claude Code's orange into gold, its white into violet, its grey past-prompt slab into
  a violet one and its green/red diff lines into gold/plum, without touching Claude Code's
  theme (map: `zach/profiles/claude-over-wow.py`, from Claude Code 2.1.325's dark theme; the
  profile also has its own violet + gold ANSI palette for basic-color output such as the
  status line). Touches VT100Terminal, VT100ScreenConfiguration, VT100ScreenMutableState,
  PTYSession.
- **Claude Dock** (`zach/claude-dock/`, 2026-11-15): the WoW panel's own app,
  `/Applications/Claude Dock.app`, so the main iTerm2 that hosts every Claude session is
  never the app WoW's panel lives in (its own Documents/Accessibility grants, its own quit,
  its own Dock icon). It is the same fork build, re-branded by `zach/claude-dock/rebrand.sh`:
  bundle id `com.zakkbates.claudedock`, executable `ClaudeDock` (so `pkill iTerm2` and
  swap-on-quit's iTerm2 path never match it), its own icon (`icon/claude-dock-icon.svg` ->
  `icon/ClaudeDock.icns` by `icon/make-icns.py`, violet + gold panel docked in a window's
  corner), no URL schemes, document types or Services, Sparkle off, re-signed with Zach's
  Developer ID (hardened runtime; Santa allows it by Team ID). Constants:
  `zach/claude-dock/claude-dock.conf`.
  - Isolation (fork hook, `sources/AppKit/main.m`): Info.plist key `ZachForkSettingsSuite`
    = `ClaudeDock` makes every launch behave like `-suite ClaudeDock`: settings in
    `~/Library/Preferences/ClaudeDock.plist` (+ `ClaudeDock.private`), files in
    `~/Library/Application Support/ClaudeDock` and `~/.config/ClaudeDock`, sockets
    `ClaudeDock.socket.*`. Any isolated instance also skips the local-network probe, the
    `iterm2:` handler registration, Sparkle and the backup update checker
    (iTermApplicationDelegate.m, iTermLaunchServices.m, iTermSoftwareUpdater.swift,
    iTermBackupUpdateChecker.swift).
  - Dock icon: clicking it brings the panel up with the keyboard (WoW activated first, the
    same end state as the hotkey); with no WoW window, an alert says the panel appears with
    it (iTermApplicationDelegate.m posts `iTermAppDockDockIconClicked`, AppDockManager
    handles it; only for isolated instances with a docked profile).
  - Settings: `seed-prefs.py` copies the main iTerm2's once (read-only on the main side):
    Default profile and globals, minus window frames, Sparkle state, hotkeys and the other
    profiles; no windows at startup, no API server, no tips, never quits when the panel's
    window closes, no suite name over the Dock icon.
  - Launcher: `hammerspoon/claude-dock.lua` (installed to `~/.hammerspoon/`): Ctrl-Opt-Cmd-C
    runs `open -g -b com.zakkbates.claudedock` while Claude Dock is not running and steps
    aside the moment it launches, so the key is Claude Dock's own while it runs.
  - Setup once it is in /Applications: `zach/claude-dock/install.sh` (seeds settings, writes
    the profile into Claude Dock's folder, moves the main iTerm2's copy to
    `~/Documents/iTerm2-builds/claude-over-wow.main-iterm2-<stamp>.json`, loads the launcher
    into Hammerspoon in place). It never launches Claude Dock.
  - First launch (Zach, once): open Claude Dock (best with WoW windowed), click Allow on the
    Documents box (the panel runs claude in `~/Documents/wow-forever-addons`). Recommended:
    System Settings > Privacy & Security > Accessibility > + > Claude Dock, then quit and
    reopen it (with the grant it follows WoW by notifications instead of polling at 10 Hz).
  - Not yet: its menus still say “About iTerm2” / “Quit iTerm2” (compiled nib strings).
- Build-time only (zach/build.sh, never committed to upstream files): nightly channel plist
  (nightly-only features on), update feeds pointed at a dead local address so a stock build
  can never install over ours, `keychain-access-groups` dropped (it needs George Nachman's
  provisioning profile).

## How updates work

- `com.zach.iterm2-fork-update` (04:00 daily, and at load: login, `install.sh`) runs
  `run-update`, which runs `update.sh`: fetch upstream, take the
  newest `v*-nightly` tag, merge `zach` onto it in `~/Documents/iTerm2-builds/worktree`,
  build signed with Zach's Developer ID (team 76Q7685NR2), stage it in
  `~/Documents/iTerm2-builds/staged/`. The `zach` branch is never rewritten. A merge
  conflict or a failed build leaves the running build alone and sends a Mac notification.
  Nothing new upstream = exits at once.
- Why `run-update` (11-12): a launchd job that starts `/bin/zsh` directly gets no access to
  `~/Documents`, so the 04:00 runs on 11-11 and 11-12 died with "can't open input file". The
  launcher is signed under its own identifier (`com.zach.iterm2-fork-update`), holds the
  Documents grant (asked for once), and `update.sh` inherits it.
- Quiet hours (Zach, 2026-11-15: “i dont think an iterm2 nightly build is going to ram spotify
  to the point of affecting playback”): the 4 AM run goes ahead during quiet hours, the one build
  allowed then. Quiet hours (`~/Documents/quiet-hours`) keep this LaunchAgent loaded and never
  stop its processes (`config.NIGHT_EXEMPT_WORK`); it runs at background QoS (efficiency cores),
  Nice 10, low-priority I/O. During quiet hours its notices are silent banners (ping-zach plays a
  sound). The swap agent stays paused until `wake`, so the night’s build installs in the morning.
- Claude Dock rides the same run: after staging iTerm2, `update.sh` re-brands the build into
  `~/Documents/iTerm2-builds/staged-claude-dock/Claude Dock.app` (+ `BUILD_ID`). A failed
  re-brand never holds back iTerm2: one Mac notification per build, exit 6 at the end, and
  the next run (even with nothing new upstream) catches Claude Dock up from the staged or
  installed iTerm2 of the same build.
- `com.zach.iterm2-fork-swap` runs `swap-on-quit`, one watcher per app: when a staged build
  is waiting and iTerm2 quits, it moves the build into `/Applications/iTerm.app` within
  milliseconds (the replaced app goes to `~/Documents/iTerm2-builds/previous/`); a staged
  Claude Dock goes into `/Applications/Claude Dock.app` whenever Claude Dock is not running
  (replaced app: `previous-claude-dock/`). Quitting one never touches the other.

## Commands

- Build now: `~/Documents/iTerm2-builds/bin/update.sh --force`
- State (both apps): `~/Documents/iTerm2-builds/bin/swap-on-quit --status`
- Install a staged Claude Dock now (it must not be running):
  `~/Documents/iTerm2-builds/bin/swap-on-quit --once --app claude-dock`
- Claude Dock setup after an install: `zach/claude-dock/install.sh`
- Run the nightly job now, as launchd does: `launchctl kickstart gui/$(id -u)/com.zach.iterm2-fork-update`
- Documents access of the launcher: `~/Documents/iTerm2-builds/bin/run-update --probe` (from a
  terminal this reports the terminal's access; the real test is a launchd run)
- Logs: `~/Documents/iTerm2-builds/logs/`
- Reinstall tooling: `zach/install.sh`

## Rollback

- Previous build: move `~/Documents/iTerm2-builds/previous/iTerm.app` back to
  `/Applications/iTerm.app` while iTerm2 is not running.
- Stock 3.7.2: `~/Documents/iTerm2-builds/iTerm-3.7.2.zip`.
- Claude Dock, previous build: move `~/Documents/iTerm2-builds/previous-claude-dock/Claude Dock.app`
  back to `/Applications/` while it is not running. Back to the panel in the main iTerm2: quit
  Claude Dock, move the newest `~/Documents/iTerm2-builds/claude-over-wow.main-iterm2-*.json`
  to `~/Library/Application Support/iTerm2/DynamicProfiles/claude-over-wow.json`, and take the
  `claude-dock` block out of `~/.hammerspoon/init.lua`.
- Stop the automation: `launchctl bootout gui/$(id -u)/com.zach.iterm2-fork-update` and
  the same for `com.zach.iterm2-fork-swap`.
