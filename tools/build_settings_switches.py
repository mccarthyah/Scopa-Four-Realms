#!/usr/bin/env python3
"""Generate the settings switches offline for crisp low-cost rendering."""
from pathlib import Path
from PIL import Image, ImageDraw

DEST = Path(__file__).resolve().parents[1] / 'assets' / 'ui'
SCALE = 4
WIDTH, HEIGHT = 144, 76


def draw_switch(enabled):
    image = Image.new('RGBA', (WIDTH * SCALE, HEIGHT * SCALE), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)

    def rect(coords):
        return tuple(int(x * SCALE) for x in coords)

    # Capsule-shaped track with a restrained metallic edge.
    d.rounded_rectangle(rect((2, 4, 142, 74)), 35 * SCALE, fill=(3, 8, 15, 140))
    d.rounded_rectangle(rect((2, 2, 142, 71)), 34 * SCALE,
                        fill=(176, 137, 65, 255) if enabled else (100, 105, 111, 255))
    d.rounded_rectangle(rect((5, 5, 139, 68)), 31 * SCALE,
                        fill=(38, 88, 57, 255) if enabled else (18, 34, 49, 255))
    d.rounded_rectangle(rect((7, 7, 137, 66)), 29 * SCALE,
                        outline=(118, 170, 108, 210) if enabled else (67, 82, 94, 220), width=2 * SCALE)
    # Discrete position markers help communicate state independently of colour.
    if enabled:
        d.rounded_rectangle(rect((28, 24, 33, 48)), 2 * SCALE, fill=(213, 235, 195, 220))
    else:
        d.ellipse(rect((106, 27, 118, 39)), outline=(151, 167, 170, 230), width=2 * SCALE)
    cx = 104 if enabled else 40
    d.ellipse(rect((cx - 29, 9, cx + 29, 67)), fill=(3, 9, 16, 105))
    d.ellipse(rect((cx - 29, 6, cx + 29, 64)),
              fill=(222, 190, 116, 255) if enabled else (155, 158, 151, 255))
    d.ellipse(rect((cx - 26, 9, cx + 26, 61)),
              fill=(250, 237, 199, 255) if enabled else (213, 217, 205, 255))
    d.arc(rect((cx - 23, 12, cx + 23, 58)), 200, 340,
          fill=(255, 255, 245, 200), width=2 * SCALE)
    image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS).save(
        DEST / ('switch_on.png' if enabled else 'switch_off.png'), optimize=True)


if __name__ == '__main__':
    DEST.mkdir(parents=True, exist_ok=True)
    draw_switch(False)
    draw_switch(True)
    print('Generated rounded settings switches in', DEST)
