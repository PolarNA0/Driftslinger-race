#!/usr/bin/env python3
"""Generate Android launcher icons (legacy + adaptive) with no dependencies."""
import math
import os
import struct
import zlib

RES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "android", "res")
BG = (11, 13, 18)
ACCENT = (110, 231, 255)
CAR = (255, 209, 102)


def _chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def png_bytes(pixels, size):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            raw += bytes(pixels[y][x])
    out = b"\x89PNG\r\n\x1a\n"
    out += _chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    out += _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += _chunk(b"IEND", b"")
    return out


def lerp(a, b, t):
    return a + (b - a) * t


def _mark(x, y, size, cx, cy, radius):
    """Colour for the icon mark, or None for transparent."""
    # road arc
    best = None
    for i in range(160):
        t = i / 159.0
        ang = math.pi * (0.55 + t * 1.05)
        rr = radius * (0.95 - 0.32 * math.sin(t * math.pi))
        px = cx + rr * math.cos(ang)
        py = cy + rr * math.sin(ang) * 0.94
        d = math.hypot(x + 0.5 - px, y + 0.5 - py)
        if best is None or d < best:
            best = d
    road_w = radius * 0.34
    if best < road_w:
        return (38, 48, 72, 255)
    if math.hypot(x + 0.5 - (cx + radius * 0.34), y + 0.5 - (cy - radius * 0.12)) < radius * 0.17:
        return (ACCENT[0], ACCENT[1], ACCENT[2], 255)
    return None


def render_legacy(size):
    px = [[(0, 0, 0, 0)] * size for _ in range(size)]
    cx = cy = size / 2.0
    radius = size * 0.44
    for y in range(size):
        for x in range(size):
            t = (y + 0.5) / size
            col = (int(lerp(BG[0], 26, t)), int(lerp(BG[1], 34, t)), int(lerp(BG[2], 52, t)), 255)
            mark = _mark(x, y, size, cx, cy, radius)
            if mark:
                col = mark
            # car dot at the road's end
            ang = math.pi * 1.6
            rr = radius * (0.95 - 0.32 * math.sin(math.pi))
            ex = cx + rr * math.cos(ang)
            ey = cy + rr * math.sin(ang) * 0.94
            if math.hypot(x + 0.5 - ex, y + 0.5 - ey) < radius * 0.2:
                col = (CAR[0], CAR[1], CAR[2], 255)
            px[y][x] = col
    return png_bytes(px, size)


def render_foreground(size):
    px = [[(0, 0, 0, 0)] * size for _ in range(size)]
    cx = cy = size / 2.0
    radius = size * 0.30
    for y in range(size):
        for x in range(size):
            mark = _mark(x, y, size, cx, cy, radius)
            if mark:
                px[y][x] = mark
            ang = math.pi * 1.6
            rr = radius * (0.95 - 0.32 * math.sin(math.pi))
            ex = cx + rr * math.cos(ang)
            ey = cy + rr * math.sin(ang) * 0.94
            if math.hypot(x + 0.5 - ex, y + 0.5 - ey) < radius * 0.22:
                px[y][x] = (CAR[0], CAR[1], CAR[2], 255)
    return png_bytes(px, size)


def main():
    densities = [("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
                 ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432)]
    for name, legacy, fg in densities:
        d = os.path.join(RES, "mipmap-" + name)
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "ic_launcher.png"), "wb").write(render_legacy(legacy))
        open(os.path.join(d, "ic_launcher_round.png"), "wb").write(render_legacy(legacy))
        open(os.path.join(d, "ic_launcher_foreground.png"), "wb").write(render_foreground(fg))
        print("wrote", name, legacy, fg)


if __name__ == "__main__":
    main()
