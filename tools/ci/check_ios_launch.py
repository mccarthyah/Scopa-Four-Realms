#!/usr/bin/env python3
"""Verify Godot exported the blank iOS launch images, not its boot logo."""
import struct
import sys
import zlib
from pathlib import Path


def validate_png(path):
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>IIBBBBB', data[16:29]) != (1, 1, 8, 6, 0, 0, 0):
        raise ValueError(f'{path}: expected a one-pixel RGBA PNG')
    chunks = []
    pos = 8
    while pos < len(data):
        size = struct.unpack('>I', data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        if kind == b'IDAT':
            chunks.append(data[pos + 8:pos + 8 + size])
        pos += size + 12
    raw = zlib.decompress(b''.join(chunks))
    # For a single zero-valued pixel, all PNG filters encode zero channels.
    if len(raw) != 5 or raw[0] > 4 or raw[1:] != b'\0\0\0\0':
        raise ValueError(f'{path}: launch pixel is not fully transparent')


def main():
    root = Path(sys.argv[1])
    for scale in ('2x', '3x'):
        matches = list(root.rglob(f'SplashImage.imageset/splash@{scale}.png'))
        if len(matches) != 1:
            raise ValueError(f'Expected one exported {scale} splash image; found {len(matches)}')
        validate_png(matches[0])
        print(f'Verified transparent iOS launch image: {matches[0]}')


if __name__ == '__main__':
    try:
        main()
    except (IndexError, OSError, ValueError, struct.error, zlib.error) as exc:
        raise SystemExit(str(exc))
