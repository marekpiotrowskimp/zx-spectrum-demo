#!/usr/bin/env python3
"""
zxgfx.py - PNG -> ZX Spectrum screen conversion helpers.

For every 8x8 cell the converter tries all ink/paper pairs (with and without
BRIGHT), dithers the cell between the two colours with an ordered Bayer
matrix and keeps the pair with the lowest error. This preserves the
fire gradients (red->yellow) and the grey dithered stone of the source.
"""

import numpy as np
from PIL import Image

ZX_RGB = np.array([
    (0, 0, 0), (0, 0, 205), (205, 0, 0), (205, 0, 205),
    (0, 205, 0), (0, 205, 205), (205, 205, 0), (205, 205, 205),
    (0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
    (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255),
], dtype=float)

BAYER4 = (np.array([
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
], dtype=float) + 0.5) / 16.0
BAYER8 = np.tile(BAYER4, (2, 2))

BLACK, BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE = range(8)


def load_256x192(path):
    """Load a PNG and centre it on a 256x192 black canvas (no stretching)."""
    img = Image.open(path).convert("RGB")
    if img.size[0] > 256 or img.size[1] > 192:
        img.thumbnail((256, 192), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (256, 192), (0, 0, 0))
    canvas.paste(img, ((256 - img.size[0]) // 2, (192 - img.size[1]) // 2))
    return np.asarray(canvas).astype(float)


def scr_offset(x, y):
    return ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | (x >> 3)


def make_attr(ink, paper, bright=False):
    return (paper << 3) | ink | (0x40 if bright else 0)


def convert_cell(cell, allowed=range(8)):
    """Return (attr, 8 bytes) for an 8x8x3 float cell."""
    best = None
    flat = cell.reshape(-1, 3)
    for bright in (0, 1):
        for i in allowed:
            for j in allowed:
                if j < i:
                    continue
                c1 = ZX_RGB[i + 8 * bright]   # paper
                c2 = ZX_RGB[j + 8 * bright]   # ink
                d = c2 - c1
                dd = float(d @ d)
                if dd == 0:
                    t = np.zeros(64)
                else:
                    t = np.clip(((flat - c1) @ d) / dd, 0, 1)
                proj = c1 + np.outer(t, d)
                # projection error + quantisation error of the dither mix
                err = ((flat - proj) ** 2).sum()
                on = t.reshape(8, 8) > BAYER8
                # coarse local average check (2x2 blocks)
                mix = np.where(on[..., None], c2, c1)
                blk = (mix.reshape(4, 2, 4, 2, 3).mean((1, 3))
                       - cell.reshape(4, 2, 4, 2, 3).mean((1, 3)))
                err += 0.5 * (blk ** 2).sum() * 4
                if bright and i == 0 and j == 0:
                    err += 1  # prefer plain black
                if best is None or err < best[0]:
                    best = (err, i, j, bright, on)
    _, paper, ink, bright, on = best
    if ink == paper:
        on[:] = False
    rows = []
    for y in range(8):
        b = 0
        for x in range(8):
            if on[y, x]:
                b |= 0x80 >> x
        rows.append(b)
    # keep ink as the brighter colour; if a cell is all paper, normalise
    return make_attr(ink, paper, bright), rows


def convert(rgb, allowed=range(8)):
    """Convert 256x192 float RGB to 6912 byte SCR."""
    bitmap = bytearray(6144)
    attrs = bytearray(768)
    for cy in range(24):
        for cx in range(32):
            cell = rgb[cy * 8:cy * 8 + 8, cx * 8:cx * 8 + 8]
            attr, rows = convert_cell(cell, allowed)
            attrs[cy * 32 + cx] = attr
            for r in range(8):
                bitmap[scr_offset(cx * 8, cy * 8 + r)] = rows[r]
    return bytes(bitmap) + bytes(attrs)


def scr_to_png(scr, path, scale=2):
    img = Image.new("RGB", (256, 192))
    px = img.load()
    for y in range(192):
        for x in range(256):
            a = scr[6144 + (y >> 3) * 32 + (x >> 3)]
            bit = scr[scr_offset(x, y)] & (0x80 >> (x & 7))
            br = 8 if a & 0x40 else 0
            c = (a & 7) if bit else ((a >> 3) & 7)
            px[x, y] = tuple(int(v) for v in ZX_RGB[c + br])
    img.resize((256 * scale, 192 * scale), Image.Resampling.NEAREST).save(path)


def saturation_mask(rgb, sat_min=60, val_min=80):
    mx = rgb.max(2)
    mn = rgb.min(2)
    return ((mx - mn) > sat_min) & (mx > val_min)
