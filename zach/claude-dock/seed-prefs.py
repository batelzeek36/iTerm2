#!/usr/bin/env python3
"""Seed Claude Dock's settings (defaults domain = its suite, ClaudeDock) from the main iTerm2's,
so the panel looks exactly as it did inside the main iTerm2 (the Default profile it inherits
from, fonts, globals), minus everything that belongs to the main iTerm2 alone.

    zach/claude-dock/seed-prefs.py            seed once; does nothing when Claude Dock already has settings
    zach/claude-dock/seed-prefs.py --force    replace Claude Dock's settings with a fresh copy
    zach/claude-dock/seed-prefs.py --dry-run  print what would be written, write nothing

The main iTerm2's settings are only read (through `defaults export`, so cfprefsd's current
values), never written. Refuses while Claude Dock runs: it would overwrite the import on quit.

Left out of the copy: window frames and saved positions (they are the main iTerm2's windows),
Sparkle's update state, a custom settings folder or dynamic-profiles path, the installation id,
and every profile but Default (the "Claude over WoW" panel profile is a dynamic profile in
Claude Dock's own DynamicProfiles folder, written by zach/profiles/claude-over-wow.py).
Set: no windows at startup, no Python API server, no tips, no update checks, never quit when
the panel's window closes, no suite name drawn over the Dock icon, the Claude Code repair
prompt answered "Not Now" (the main iTerm2 owns that integration).
"""
import os
import plistlib
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MAIN_DOMAIN = "com.googlecode.iterm2"


def conf():
    values = {}
    with open(os.path.join(HERE, "claude-dock.conf")) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key] = value.strip('"')
    for key in ("SUITE", "BUNDLE_ID", "EXECUTABLE", "APP_NAME"):
        if not values.get(key):
            sys.exit("seed-prefs: %s missing from claude-dock.conf" % key)
    return values


def export(domain):
    """The domain's current values, or {} when it has none."""
    result = subprocess.run(["/usr/bin/defaults", "export", domain, "-"], capture_output=True)
    if result.returncode != 0 or not result.stdout.strip():
        return {}
    try:
        value = plistlib.loads(result.stdout)
    except Exception as e:  # a corrupt export is not something to build on
        sys.exit("seed-prefs: could not parse `defaults export %s`: %s" % (domain, e))
    if not isinstance(value, dict):
        sys.exit("seed-prefs: `defaults export %s` is not a dictionary" % domain)
    return value


def claude_dock_running(executable):
    result = subprocess.run(["/usr/bin/pgrep", "-x", executable], capture_output=True, text=True)
    return result.returncode == 0


DROP_PREFIXES = ("NSWindow Frame", "NoSyncFrame_", "SU")
DROP_KEYS = {
    "NoSyncSavedWindowPositions",
    "NoSyncInstallationId",
    "NoSyncBackupUpdateLastCheck",
    "NoSyncLastShutdownWasClean",
    "NoSyncRestoreWindowsCount",
    "NoSyncWindowCornerRadiusCache",
    "PrefsCustomFolder",
    "LoadPrefsFromCustomFolder",
    "DynamicProfilesPath",
    "New Bookmarks",
}
HOTKEY_PROFILE_KEYS = (
    "Has Hotkey", "HotKey Key Code", "HotKey Characters", "HotKey Characters Ignoring Modifiers",
    "HotKey Modifier Flags", "HotKey Activated By Modifier", "HotKey Modifier Activation",
    "HotKey Alternate Shortcuts",
)
SETTINGS = {
    "OpenNoWindowsAtStartup": True,
    "QuitWhenAllWindowsClosed": False,
    "EnableAPIServer": False,
    "LoadPrefsFromCustomFolder": False,
    "NoSyncTipsDisabled": True,
    "NoSyncPermissionToShowTip": False,
    "ShowSuiteNameInDockIcon": False,
    "SUEnableAutomaticChecks": False,
    "SUAutomaticallyUpdate": False,
    "SUHasLaunchedBefore": True,
    "NoSyncSuppressClaudeCodeIntegrationRepairPrompt": True,
    "NoSyncSuppressClaudeCodeIntegrationRepairPrompt_selection": 1,
}
# Sparkle keeps its own state in the app's standard domain (the bundle id), not the suite.
BUNDLE_DOMAIN_SETTINGS = {
    "SUEnableAutomaticChecks": False,
    "SUAutomaticallyUpdate": False,
    "SUHasLaunchedBefore": True,
}


def seeded(main):
    out = {}
    for key, value in main.items():
        if key in DROP_KEYS or key.startswith(DROP_PREFIXES):
            continue
        out[key] = value
    default_guid = main.get("Default Bookmark Guid")
    profiles = main.get("New Bookmarks")
    if not isinstance(profiles, list):
        sys.exit("seed-prefs: the main iTerm2 has no profile list")
    default = next((p for p in profiles if isinstance(p, dict) and p.get("Guid") == default_guid), None)
    if default is None:
        default = next((p for p in profiles if isinstance(p, dict) and p.get("Name") == "Default"), None)
    if default is None:
        sys.exit("seed-prefs: the main iTerm2 has no Default profile to copy")
    default = dict(default)
    # The main iTerm2 owns every global shortcut; a copy would fight it for the same key.
    for key in HOTKEY_PROFILE_KEYS:
        default.pop(key, None)
    default["Has Hotkey"] = False
    out["New Bookmarks"] = [default]
    out["Default Bookmark Guid"] = default["Guid"]
    out.update(SETTINGS)
    return out


def write_domain(domain, values):
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "seed.plist")
        with open(path, "wb") as f:
            plistlib.dump(values, f, fmt=plistlib.FMT_BINARY)
        subprocess.run(["/usr/bin/defaults", "import", domain, path], check=True)


def main():
    args = sys.argv[1:]
    if any(a not in ("--force", "--dry-run") for a in args):
        sys.exit(__doc__)
    force, dry = "--force" in args, "--dry-run" in args
    c = conf()
    suite, bundle_id = c["SUITE"], c["BUNDLE_ID"]
    # Reading is safe while Claude Dock runs; only a write needs it quit. So a re-run of
    # install.sh with Claude Dock open (it already has settings) goes on to the other steps.
    existing = export(suite)
    if existing and not force:
        print("seed-prefs: %s already has settings (%d keys); left as they are (--force replaces them)"
              % (c["APP_NAME"], len(existing)))
        return
    if not dry and claude_dock_running(c["EXECUTABLE"]):
        sys.exit("seed-prefs: %s is running; quit it first (it would write its settings back on quit)" % c["APP_NAME"])
    main_values = export(MAIN_DOMAIN)
    if not main_values:
        sys.exit("seed-prefs: the main iTerm2 has no settings to copy")
    values = seeded(main_values)
    bundle_values = dict(export(bundle_id))
    bundle_values.update(BUNDLE_DOMAIN_SETTINGS)
    if dry:
        dropped = sorted(k for k in main_values if k not in values)
        print("would write %d keys to %s (dropped %d: %s)" % (len(values), suite, len(dropped), ", ".join(dropped)))
        print("profiles:", [p.get("Name") for p in values["New Bookmarks"]])
        for key in sorted(SETTINGS):
            print("  %s = %r" % (key, values[key]))
        print("would write %s: %r" % (bundle_id, BUNDLE_DOMAIN_SETTINGS))
        return
    write_domain(suite, values)
    write_domain(bundle_id, bundle_values)
    check = export(suite)
    if check.get("OpenNoWindowsAtStartup") is not True or len(check.get("New Bookmarks", [])) != 1:
        sys.exit("seed-prefs: %s did not read back as written" % suite)
    print("seed-prefs: wrote %d keys to %s (profile: %s) and Sparkle's state to %s"
          % (len(check), suite, check["New Bookmarks"][0].get("Name"), bundle_id))


if __name__ == "__main__":
    main()
