#!/usr/bin/env python3
"""Render claude-dock-icon.svg into ClaudeDock.icns (every size macOS asks for, each drawn from
the vector, not scaled from one bitmap). Needs cairosvg (pip) and Apple's iconutil.

    zach/claude-dock/icon/make-icns.py      rewrites ClaudeDock.icns next to this script

The .icns is committed, so building Claude Dock never needs this; run it after editing the SVG.
"""
import os
import subprocess
import sys
import tempfile

import cairosvg

HERE = os.path.dirname(os.path.abspath(__file__))
SVG = os.path.join(HERE, "claude-dock-icon.svg")
OUT = os.path.join(HERE, "ClaudeDock.icns")
# iconset name -> pixel size
SIZES = {
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
}


def main():
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "ClaudeDock.iconset")
        os.mkdir(iconset)
        for name, size in SIZES.items():
            cairosvg.svg2png(url=SVG, write_to=os.path.join(iconset, name),
                             output_width=size, output_height=size)
        # iconutil insists on the .icns extension; write in the temp folder, then rename into place.
        new = os.path.join(tmp, "ClaudeDock.icns")
        subprocess.run(["/usr/bin/iconutil", "--convert", "icns", "--output", new, iconset], check=True)
        os.replace(new, OUT)
    print("wrote", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    sys.exit(main())
