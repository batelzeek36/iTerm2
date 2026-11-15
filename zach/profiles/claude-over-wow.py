#!/usr/bin/env python3
"""Writes the "Claude over WoW" dynamic profile: a Claude Code panel docked in World of
Warcraft's ElvUI right-chat slot (fork feature sources/AppDock, see zach/README.md).

    zach/profiles/claude-over-wow.py            write ~/Library/Application Support/iTerm2/DynamicProfiles/claude-over-wow.json
    zach/profiles/claude-over-wow.py --test D   write a copy for a -suite test instance into D, running a
                                                color replay instead of claude, on Ctrl-Opt-Cmd-J

The look is the approved comp of 2026-11-14 (wow-forever-addons/mac/claude-overlay-comp,
mode 1 "Chat dock"): violet text #cdb8ff, gold accents #f3cd5a, near-black backdrop at 60%.
"""
import json
import os
import sys

WOW = "/Applications/World of Warcraft/_forever_"
ELVUI = WOW + "/WTF/Account/809277904#1/SavedVariables/ElvUI.lua"
WORKDIR = os.path.expanduser("~/Documents/wow-forever-addons")

def color(hex_rgb):
    v = int(hex_rgb.lstrip("#"), 16)
    return {"Red Component": ((v >> 16) & 255) / 255, "Green Component": ((v >> 8) & 255) / 255,
            "Blue Component": (v & 255) / 255, "Alpha Component": 1, "Color Space": "sRGB"}

VIOLET, GOLD, BACKDROP = "#cdb8ff", "#f3cd5a", "#060607"

# Claude Code's dark theme paints these in 24-bit color; in this panel they become the
# comp's palette. Claude Code's own settings, and every other session, are untouched.
REMAP = {
    "#d77757": GOLD,       # claude: the accent orange (bullets, spinner)
    "#eb9f7f": "#f8dd8c",  # claudeShimmer
    "#4eba65": GOLD,       # success
    "#ffffff": VIOLET,     # text
    "#999999": "#9a88d0",  # inactive -> muted violet
    "#c1c1c1": "#b6a6e6",  # inactiveShimmer
    "#505050": "#6c5f9a",  # subtle -> faint violet
    "#888888": "#5f5582",  # promptBorder
    "#a6a6a6": "#7a6fa0",  # promptBorderShimmer
}

def profile(test):
    p = {
        "Name": "Claude over WoW",
        "Guid": "zach-claude-over-wow-0001",
        "Dynamic Profile Parent Name": "Default",
        "Tags": ["wow", "overlay"],
        "Custom Command": "Yes",
        "Command": "/bin/zsh -lic 'cd ~/Documents/wow-forever-addons && exec claude'",
        "Custom Directory": "Yes",
        "Working Directory": WORKDIR,
        # The fork docks this profile; an unmodified iTerm2 ignores the Dock keys.
        "Dock To App Bundle ID": "com.blizzard.worldofwarcraft",
        "Dock To App Path": WOW + "/World of Warcraft.app",
        "Dock Window Title": "World of Warcraft",
        "Dock ElvUI SavedVariables": ELVUI,
        "Dock ElvUI Panel": "RightChat",
        "Dock Header Title": "Claude",
        "Dock Header Subtitle": "wow-forever",
        # Ctrl-Opt-Cmd-C: focus the panel / give the keyboard back to WoW. Shift adds hide/show.
        "Has Hotkey": True,
        "HotKey Key Code": 8,
        "HotKey Characters": "c",
        "HotKey Characters Ignoring Modifiers": "c",
        "HotKey Modifier Flags": 1835008,
        "HotKey Activated By Modifier": False,
        "HotKey Window Floats": True,
        "HotKey Window AutoHides": False,
        "HotKey Window Animates": False,
        "Space": -1,
        "Window Type": 12,
        "Columns": 52,
        "Rows": 12,
        "Normal Font": "Menlo-Regular 10",
        "Use Non-ASCII Font": False,
        "Horizontal Spacing": 1,
        "Vertical Spacing": 1,
        "Use Separate Colors for Light and Dark Mode": False,
        "Background Color": color(BACKDROP),
        "Foreground Color": color(VIOLET),
        "Bold Color": color("#e4daff"),
        "Use Bold Color": True,
        "Cursor Color": color(VIOLET),
        "Cursor Text Color": color(BACKDROP),
        "Selection Color": color("#3d3459"),
        "Selected Text Color": color("#f1ebff"),
        "Link Color": color(GOLD),
        "Transparency": 0.4,
        "Blur": False,
        "Initial Use Transparency": True,
        "Minimum Contrast": 0,
        "Show Status Bar": False,
        "Silence Bell": True,
        "Visual Bell": False,
        "Flashing Bell": False,
        "True Color Remap": REMAP,
    }
    if test:
        p["Command"] = test["command"]
        p["HotKey Key Code"] = 38
        p["HotKey Characters"] = "j"
        p["HotKey Characters Ignoring Modifiers"] = "j"
    return p

def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--test":
        out_dir = sys.argv[2]
        test = {"command": os.path.join(out_dir, "..", "replay.sh")}
    elif len(sys.argv) == 1:
        out_dir = os.path.expanduser("~/Library/Application Support/iTerm2/DynamicProfiles")
        test = None
    else:
        sys.exit(__doc__)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "claude-over-wow.json")
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"Profiles": [profile(test)]}, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
    print("wrote", path)

if __name__ == "__main__":
    main()
