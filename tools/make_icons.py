#!/usr/bin/env python3
"""Generate the app icons as PNGs with no third-party dependencies."""
import math
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "icons")

BG_TOP = (14, 18, 30)
BG_BOT = (26, 34, 52)
ACCENT = (110, 231, 255)   # the pole / road edge
CAR = (255, 209, 102)      # the car


def _chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


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


def render(size, maskable=False):
    px = [[(0, 0, 0, 0)] * size for _ in range(size)]
    cx = cy = size / 2.0
    pad = size * (0.26 if maskable else 0.10)
    radius = (size - 2 * pad) / 2.0
    # The road: a smooth curve sweeping up the icon, drawn as a thick stroke.
    # Two control-ish points make an arc that reads as a corner being carved.
    pts = []
    for i in range(240):
        t = i / 239.0
        ang = math.pi * (0.55 + t * 1.05)
        rr = radius * (0.92 - 0.30 * math.sin(t * math.pi))
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang) * 0.92))
    pole = (cx + radius * 0.30, cy - radius * 0.10)
    car = pts[-1]
    road_w = max(2.5, size * 0.11)
    pole_r = max(2.0, size * 0.075)
    car_r = max(3.0, size * 0.10)

    for y in range(size):
        for x in range(size):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d > radius + 1:
                continue
            t = (y + 0.5) / size
            col = (int(lerp(BG_TOP[0], BG_BOT[0], t)),
                   int(lerp(BG_TOP[1], BG_BOT[1], t)),
                   int(lerp(BG_TOP[2], BG_BOT[2], t)), 255)
            edge = radius - d
            if edge < 1.0:
                col = (col[0], col[1], col[2], int(255 * max(0.0, edge)))
            # road stroke
            best = min((math.hypot(x + 0.5 - p[0], y + 0.5 - p[1]) for p in pts))
            if best < road_w / 2:
                a = 1.0 - max(0.0, (best - road_w / 2 + 1.6) / 1.6)
                col = (int(lerp(col[0], 40, a)), int(lerp(col[1], 52, a)),
                       int(lerp(col[2], 78, a)), col[3])
                if best > road_w / 2 - max(1.2, size * 0.018):
                    col = (int(lerp(col[0], ACCENT[0], a * 0.85)),
                           int(lerp(col[1], ACCENT[1], a * 0.85)),
                           int(lerp(col[2], ACCENT[2], a * 0.85)), col[3])
            # pole
            if math.hypot(x + 0.5 - pole[0], y + 0.5 - pole[1]) < pole_r:
                col = (ACCENT[0], ACCENT[1], ACCENT[2], 255)
            # car, orbiting at the end of the road
            if math.hypot(x + 0.5 - car[0], y + 0.5 - car[1]) < car_r:
                col = (CAR[0], CAR[1], CAR[2], 255)
            px[y][x] = col
    return png_bytes(px, size)


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = [
        ("icon-192.png", 192, False),
        ("icon-512.png", 512, False),
        ("maskable-512.png", 512, True),
        ("apple-touch-icon.png", 180, True),
    ]
    for name, size, maskable in jobs:
        data = render(size, maskable)
        with open(os.path.join(OUT, name), "wb") as fh:
            fh.write(data)
        print("wrote", name, size, len(data), "bytes")


if __name__ == "__main__":
    main()
