#!/usr/bin/env python3
"""Writes the "Claude over WoW" dynamic profile: a Claude Code panel docked in World of
Warcraft's ElvUI right-chat slot (fork feature sources/AppDock, see zach/README.md).

    zach/profiles/claude-over-wow.py            write ~/Library/Application Support/ClaudeDock/DynamicProfiles/claude-over-wow.json
    zach/profiles/claude-over-wow.py --test D   write a copy for a -suite test instance into D, running a
                                                color replay instead of claude, on Ctrl-Opt-Cmd-J

The panel runs in Claude Dock (zach/claude-dock), its own app, never in the main iTerm2: Claude
Dock reads dynamic profiles from its suite's Application Support folder (the suite name comes
from zach/claude-dock/claude-dock.conf). The main iTerm2 must not have this profile: it would
fight Claude Dock for the hotkey.

The look is the approved comp of 2026-11-14 (wow-forever-addons/mac/claude-overlay-comp,
mode 1 "Chat dock"): violet text #cdb8ff, gold accents #f3cd5a, near-black backdrop at 60%.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

WOW = "/Applications/World of Warcraft/_forever_"
ELVUI = WOW + "/WTF/Account/809277904#1/SavedVariables/ElvUI.lua"
WORKDIR = os.path.expanduser("~/Documents/wow-forever-addons")

def color(hex_rgb):
    v = int(hex_rgb.lstrip("#"), 16)
    return {"Red Component": ((v >> 16) & 255) / 255, "Green Component": ((v >> 8) & 255) / 255,
            "Blue Component": (v & 255) / 255, "Alpha Component": 1, "Color Space": "sRGB"}

VIOLET, GOLD, BACKDROP = "#cdb8ff", "#f3cd5a", "#060607"

# Claude Code's dark theme (2.1.325) paints these in 24-bit color, as text and as backgrounds;
# in this panel they become the comp's palette. Claude Code's own settings, and every other
# session, are untouched. Diffs stay add/remove: added lines on dark gold, removed on plum.
REMAP = {
    # text
    "#d77757": GOLD,       # claude: the accent orange (bullets, spinner, Clawd)
    "#eb9f7f": "#f8dd8c",  # claudeShimmer
    "#4eba65": GOLD,       # success
    "#ffffff": VIOLET,     # text
    "#999999": "#9a88d0",  # inactive -> muted violet
    "#c1c1c1": "#b6a6e6",  # inactiveShimmer
    "#505050": "#6c5f9a",  # subtle -> faint violet
    "#888888": "#5f5582",  # promptBorder
    "#a6a6a6": "#7a6fa0",  # promptBorderShimmer
    "#b1b9f9": GOLD,       # permission / suggestion / remember: the prompt that needs him
    "#cfd7ff": "#f8dd8c",  # permissionShimmer
    "#93a5ff": "#b6a6e6",  # claudeBlue (system spinner)
    "#b1c3ff": VIOLET,     # claudeBlueShimmer
    "#fd5db1": "#e0a8f0",  # bashBorder: pink -> orchid
    "#48968c": "#9a88d0",  # planMode: teal -> muted violet
    "#4782c8": "#9a88d0",  # ide
    "#00cccc": "#a9b8f2",  # background tasks: teal -> periwinkle
    "#ff6b80": "#f08ca0",  # error: a softer rose
    "#ffc107": "#f2b45a",  # warning: amber, kept apart from the gold
    "#ffdf39": "#f8dd8c",  # warningShimmer
    "#7ab4e8": "#a9b8f2",  # briefLabelYou
    "#ff7814": GOLD,       # fastMode
    "#ffa546": "#f8dd8c",  # fastModeShimmer
    "#505370": "#4a4366",  # rate_limit_empty
    "#af87ff": VIOLET,     # autoAccept / skill / merged ("accept edits on")
    "#d0b4ff": "#e4daff",  # autoAcceptShimmer
    # code in diffs (Claude Code highlights it with Monokai)
    "#f8f8f2": VIOLET,     # plain code
    "#f92672": "#e0a8f0",  # keywords -> orchid
    "#a6e22e": "#a9b8f2",  # function names -> periwinkle
    "#e6db74": "#f8dd8c",  # strings -> light gold
    "#ae81ff": GOLD,       # numbers / constants
    "#be84ff": GOLD,       # numbers in diff lines
    "#66d9ef": "#b6a6e6",  # storage / types -> lavender
    "#fd971f": "#f2c46a",  # parameters -> soft amber
    "#75715e": "#6c5f9a",  # comments -> faint violet
    "#dc5a5a": "#f08ca0",  # diff "-" marker -> rose
    "#50c850": GOLD,       # diff "+" marker -> gold
    # backgrounds (drawn at the panel's 40% see-through like its own backdrop)
    "#373737": "#2b2342",  # userMessageBackground: past prompts on a violet slab
    "#464646": "#372d55",  # userMessageBackgroundHover
    "#262626": "#1d1929",  # composerSidebarBackground
    "#264f78": "#3d3459",  # selectionBg
    "#413c41": "#33283f",  # bashMessageBackgroundColor
    "#374146": "#2d2a45",  # memoryBackgroundColor
    "#225c2b": "#4b3f16",  # diffAdded: dark gold
    "#7a2936": "#5a2347",  # diffRemoved: plum
    "#47584a": "#3b3424",  # diffAddedDimmed
    "#69484d": "#46303f",  # diffRemovedDimmed
    "#38a660": "#8c7424",  # diffAddedWord: brighter gold
    "#b3596b": "#93407a",  # diffRemovedWord: brighter plum
    "#022800": "#3e3414",  # transcript diff, added line: dark gold
    "#044700": "#6b571b",  # transcript diff, added word
    "#3d0100": "#4a1d3b",  # transcript diff, removed line: plum
    "#5c0200": "#7a3466",  # transcript diff, removed word
}

# Colors near a key (within this RGB distance) move with it: the spinner's shimmer and stall
# colors are animated steps around Claude Code's orange, and would otherwise flicker orange.
REMAP_TOLERANCE = 32

# The 16 ANSI colors in the same violet + gold family, for anything that prints basic ANSI
# (his status line: cyan directory, magenta model, yellow cost).
ANSI = [
    "#1e1a2b", "#f08ca0", "#e2d08e", GOLD, "#9a88d0", "#e0a8f0", "#a9b8f2", VIOLET,
    "#6c5f9a", "#ffa8b8", "#f0e2a8", "#f8dd8c", "#b6a6e6", "#ecc2f7", "#c4cff8", "#f1ebff",
]

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
        # Default's purple progress line would cut across the header while claude works; the
        # gold spinner line already says it is working.
        "Enable Progress Bars": False,
        "Silence Bell": True,
        "Visual Bell": False,
        "Flashing Bell": False,
        "True Color Remap": REMAP,
        "True Color Remap Tolerance": REMAP_TOLERANCE,
        # Nothing inherited from Default may reshape the panel: Default carries iTerm2's Claude
        # Code triggers, which would enter the Claude Code workgroup (extra panes and a
        # toolbar) inside the game panel the moment claude starts.
        "Triggers": [],
    }
    for i, hex_rgb in enumerate(ANSI):
        p["Ansi %d Color" % i] = color(hex_rgb)
    if test:
        p["Command"] = test["command"]
        p["HotKey Key Code"] = 38
        p["HotKey Characters"] = "j"
        p["HotKey Characters Ignoring Modifiers"] = "j"
    return p

def claude_dock_suite():
    """Claude Dock's settings suite, which names its Application Support folder."""
    path = os.path.join(HERE, "..", "claude-dock", "claude-dock.conf")
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("SUITE="):
                suite = line.split("=", 1)[1].strip().strip('"')
                if suite.isalnum():
                    return suite
    sys.exit("claude-over-wow: no valid SUITE in %s" % os.path.normpath(path))

def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--test":
        out_dir = sys.argv[2]
        test = {"command": os.path.join(out_dir, "..", "replay.sh")}
    elif len(sys.argv) == 1:
        out_dir = os.path.expanduser("~/Library/Application Support/%s/DynamicProfiles" % claude_dock_suite())
        test = None
    else:
        sys.exit(__doc__)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "claude-over-wow.json")
    text = json.dumps({"Profiles": [profile(test)]}, indent=2, ensure_ascii=False) + "\n"
    try:
        with open(path) as f:
            if f.read() == text:
                # A running Claude Dock reloads its profiles on any change in the folder.
                print("unchanged", path)
                return
    except FileNotFoundError:
        pass
    # The temp name starts with a dot: iTerm2 loads every other file in the folder, so a
    # "claude-over-wow.json.tmp" next to the profile was a second profile with the same Guid
    # (the "Two dynamic profiles have the same Guid" box, 2026-11-15).
    tmp = os.path.join(out_dir, ".claude-over-wow.json.tmp")
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)
    print("wrote", path)

if __name__ == "__main__":
    main()
