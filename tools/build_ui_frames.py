#!/usr/bin/env python3
"""Draw stretchable Four Realms frames offline; never render/readback at runtime."""
from pathlib import Path
from PIL import Image, ImageDraw

DEST = Path(__file__).resolve().parents[1] / 'assets' / 'ui'
DEST.mkdir(parents=True, exist_ok=True)
N, SCALE = 96, 4
S = N * SCALE


def render(name, fill, rim, inner, *, transparent=False, glow=None):
    image = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)
    def box(inset): return (inset*SCALE, inset*SCALE, (N-inset)*SCALE-1, (N-inset)*SCALE-1)
    # Outer dark engraving, bright metal, recessed line and dark interior.
    d.rounded_rectangle(box(1), radius=19*SCALE, fill=(4, 8, 15, 235))
    d.rounded_rectangle(box(2), radius=18*SCALE, fill=rim)
    d.rounded_rectangle(box(4), radius=16*SCALE, fill=(61, 46, 28, 255) if glow is None else (34, 72, 28, 255))
    d.rounded_rectangle(box(5), radius=15*SCALE, fill=inner)
    d.rounded_rectangle(box(7), radius=13*SCALE, fill=fill if not transparent else (0, 0, 0, 0))
    # Restrained corner filigree: contained in the nine-slice corners.
    for xsign in (1, -1):
        for ysign in (1, -1):
            x = 12 if xsign == 1 else N - 12
            y = 12 if ysign == 1 else N - 12
            xx, yy = x*SCALE, y*SCALE
            d.ellipse((xx-2*SCALE, yy-2*SCALE, xx+2*SCALE, yy+2*SCALE), fill=glow or (255, 222, 137, 220))
            d.line([(x + xsign*4)*SCALE, yy, (x + xsign*9)*SCALE, yy], fill=inner, width=SCALE)
            d.line([xx, (y + ysign*4)*SCALE, xx, (y + ysign*9)*SCALE], fill=inner, width=SCALE)
    image = image.resize((N, N), Image.Resampling.LANCZOS)
    image.save(DEST / (name+'.png'), optimize=True)

render('panel', (13, 27, 44, 250), (170, 125, 52, 255), (241, 204, 112, 255))
render('button', (17, 33, 50, 255), (181, 135, 52, 255), (255, 218, 121, 255))
render('button_hover', (31, 60, 55, 255), (116, 183, 44, 255), (205, 255, 133, 255), glow=(193, 255, 112, 255))
render('button_gold', (208, 159, 66, 255), (117, 72, 20, 255), (255, 228, 148, 255))
render('frame', (0, 0, 0, 0), (186, 141, 65, 255), (249, 216, 138, 255), transparent=True)
render('frame_active', (0, 0, 0, 0), (124, 200, 50, 255), (212, 255, 159, 255), transparent=True, glow=(205, 255, 148, 255))
for name, color in [('felt_green',(23, 67, 46,255)),('felt_blue',(20, 39, 62,255)),('felt_red',(62, 30, 33,255)),('felt_purple',(40, 32, 56,255))]:
    render(name, color, (165, 122, 53, 255), (248, 211, 125, 255))
def chip(name, fill, rim):
    image = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)
    d.rounded_rectangle((SCALE, SCALE, S-SCALE-1, S-SCALE-1), radius=15*SCALE, fill=rim)
    d.rounded_rectangle((3*SCALE, 3*SCALE, S-3*SCALE-1, S-3*SCALE-1), radius=13*SCALE, fill=fill)
    image.resize((N, N), Image.Resampling.LANCZOS).save(DEST / (name+'.png'), optimize=True)

chip('chip', (16, 30, 47, 255), (106, 93, 61, 255))
chip('chip_active', (48, 43, 25, 255), (196, 156, 67, 255))
print('Generated 12 stretchable UI frames in', DEST)
