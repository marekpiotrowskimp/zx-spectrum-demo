#!/usr/bin/env python3
"""contact.py - combine harness screenshots into one contact sheet."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

files = sorted(Path(sys.argv[1]).glob("frame_*.png"))
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 6
w, h = 320, 240
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * (h + 14)), (40, 40, 40))
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    x, y = (i % cols) * w, (i // cols) * (h + 14)
    sheet.paste(Image.open(f), (x, y + 14))
    d.text((x + 4, y + 1), f.stem, fill=(255, 255, 255))
sheet.save(sys.argv[2])
