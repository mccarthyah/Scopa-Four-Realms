#!/usr/bin/env python3
"""Build the shipped atlas offline from the supplied 4x10 card sheets.

Requires Python 3, Pillow, numpy and opencv-python. The original sheets and
three existing card backs live in tools/card_sources (ignored by Godot so they
are not included in builds). This never runs at game startup. The output keeps
Godot's 8-column, 208x292-cell atlas and maps rank-major IDs: (rank-1)*4+suit.
"""
from pathlib import Path
import argparse

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools" / "card_sources"
OUT = ROOT / "assets" / "cards" / "card_atlas.png"
SUITS = ("forge", "grove", "horde", "crown")
CELL = (208, 292)
# The source art is taller and narrower than the game's hit boxes. Preserve its
# proportions: centre it in a common 180px-wide slot, with transparent margins.
ART_W = 180
X = (20, 320, 620, 920, 1220, 1520)
Y = ((15, 490), (500, 978))


def extract(image: Image.Image, index: int, name: str) -> Image.Image:
    col, row = index % 5, index // 5
    crop = np.array(image.crop((X[col], Y[row][0], X[col + 1], Y[row][1])).convert("RGB"))
    # The luminous gold/white frame is enclosed. Closing tiny gaps connects the
    # outline; filling its external contour removes the sheet's black/blue
    # background while retaining dark details inside the card and the gemstones.
    bright = ((crop[:, :, 0] > 90) & (crop[:, :, 1] > 55) & (crop[:, :, 2] > 15)).astype(np.uint8) * 255
    contour = None
    # Some red Horde frames have small dark gaps. Close increasingly wide gaps,
    # stopping as soon as the frame forms a complete, filled silhouette.
    for kernel in (9, 13, 17, 23):
        closed = cv2.morphologyEx(bright, cv2.MORPH_CLOSE, np.ones((kernel, kernel), np.uint8))
        contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            continue
        candidate = max(contours, key=cv2.contourArea)
        x, y, w, h = cv2.boundingRect(candidate)
        if 260 <= w <= 300 and 440 <= h <= 475 and cv2.contourArea(candidate) > 112000:
            contour = candidate
            break
    if contour is None:
        raise ValueError(f"{name} {index + 1}: could not isolate a complete card")
    # Make a clean common silhouette rather than using the irregular bright
    # pixels as an alpha edge. Some frames (especially Horde) have black gaps
    # in the outer glow, which would otherwise punch holes through the border.
    # It is a rounded card body plus the two protruding diamond ornaments.
    mask_image = Image.new("L", (crop.shape[1], crop.shape[0]), 0)
    draw = ImageDraw.Draw(mask_image)
    radius = round(w * 0.135)
    body_top, body_bottom = y + round(h * 0.032), y + h - round(h * 0.032)
    draw.rounded_rectangle((x, body_top, x + w - 1, body_bottom), radius=radius, fill=255)
    cx = x + (w - 1) / 2
    half_diamond = w * 0.123
    diamond_h = h * 0.134
    draw.polygon(((cx, y), (cx + half_diamond, y + diamond_h / 2),
                  (cx, y + diamond_h), (cx - half_diamond, y + diamond_h / 2)), fill=255)
    draw.polygon(((cx, y + h - 1), (cx + half_diamond, y + h - diamond_h / 2),
                  (cx, y + h - diamond_h), (cx - half_diamond, y + h - diamond_h / 2)), fill=255)
    mask = cv2.GaussianBlur(np.array(mask_image), (3, 3), 0.55)
    rgba = np.dstack((crop, mask))
    # Crop tight around the contour, including the one-pixel anti-aliased edge.
    x0, y0 = max(0, x - 2), max(0, y - 2)
    x1, y1 = min(crop.shape[1], x + w + 2), min(crop.shape[0], y + h + 2)
    tile = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
    tile.thumbnail((ART_W, CELL[1]), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", CELL, (0, 0, 0, 0))
    out.alpha_composite(tile, ((CELL[0] - tile.width) // 2, (CELL[1] - tile.height) // 2))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the shipped atlas without overwriting it")
    args = parser.parse_args()
    atlas = Image.new("RGBA", (CELL[0] * 8, CELL[1] * 6), (0, 0, 0, 0))
    for faction, name in enumerate(SUITS):
        image = Image.open(SOURCE / f"{name}.png")
        if image.size != (1536, 1024):
            raise ValueError(f"Unexpected {name} sheet size: {image.size}")
        for rank in range(1, 11):
            tile = extract(image, rank - 1, name)
            idx = (rank - 1) * 4 + faction
            atlas.alpha_composite(tile, ((idx % 8) * CELL[0], (idx // 8) * CELL[1]))
    backs = Image.open(SOURCE / "card_backs.png").convert("RGBA")
    if backs.size != (CELL[0] * 3, CELL[1]):
        raise ValueError(f"Unexpected card back sheet size: {backs.size}")
    for i in range(3):
        idx = 40 + i
        atlas.alpha_composite(backs.crop((i * CELL[0], 0, (i + 1) * CELL[0], CELL[1])),
                              ((idx % 8) * CELL[0], (idx // 8) * CELL[1]))
    if args.check:
        existing = Image.open(OUT).convert("RGBA")
        if existing.size != atlas.size or existing.tobytes() != atlas.tobytes():
            raise SystemExit("Atlas does not match the four source sheets and card backs")
        print("Atlas matches all 40 source cards and 3 backs in rank-major order")
    else:
        atlas.save(OUT, optimize=True)
        print(f"Saved {OUT} ({atlas.width}x{atlas.height}, 40 faces and 3 backs)")


if __name__ == "__main__":
    main()
