#!/usr/bin/env python3
"""Render the Vault Boy drawable used by the Pip-Boy watch face.

No third-party imaging library is available on this box, so this does its own
rasterising: paint shapes into a supersampled RGBA buffer, box-filter it down,
then write a PNG with zlib.

Everything is authored in a 92x122 design space and scaled by KSCALE on the way
out, so the sprite can be enlarged without re-tuning every coordinate.

Two passes only:
  1. dark rim silhouettes (the hairline outline in the Fallout drawing)
  2. green fills inset from those rims, plus the face/detail linework

Keeping the dark linework sparse matters: at ~100 px tall on a watch, heavy
detail collapses into a blob.
"""
import math
import os
import struct
import zlib

W, H = 92, 122
KSCALE = 1.10
SS = 6  # supersample factor

OUT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                 "resources", "drawables", "vaultboy.png")
)

GREEN = (60, 255, 60, 255)
DARK = (6, 30, 6, 255)
BG = (0, 0, 0, 0)

IW = int(round(W * KSCALE * SS))
IH = int(round(H * KSCALE * SS))
F = KSCALE * SS

buf = bytearray(bytes(BG) * (IW * IH))


def px(x, y, color):
    if 0 <= x < IW and 0 <= y < IH:
        i = (y * IW + x) * 4
        buf[i] = color[0]
        buf[i + 1] = color[1]
        buf[i + 2] = color[2]
        buf[i + 3] = color[3]


def s(v):
    return v * F


def disc(cx, cy, r, color):
    cx, cy, r = s(cx), s(cy), s(r)
    for y in range(max(0, int(cy - r) - 1), min(IH, int(cy + r) + 2)):
        dy = y + 0.5 - cy
        if abs(dy) > r:
            continue
        half = math.sqrt(max(0.0, r * r - dy * dy))
        for x in range(max(0, int(cx - half) - 1), min(IW, int(cx + half) + 2)):
            if abs(x + 0.5 - cx) <= half:
                px(x, y, color)


def rect(x0, y0, x1, y1, color):
    for y in range(max(0, int(s(y0))), min(IH, int(math.ceil(s(y1))))):
        if not (s(y0) <= y + 0.5 <= s(y1)):
            continue
        for x in range(max(0, int(s(x0))), min(IW, int(math.ceil(s(x1))))):
            if s(x0) <= x + 0.5 <= s(x1):
                px(x, y, color)


def rrect(x0, y0, x1, y1, r, color):
    if r <= 0:
        rect(x0, y0, x1, y1, color)
        return
    rect(x0 + r, y0, x1 - r, y1, color)
    rect(x0, y0 + r, x1, y1 - r, color)
    disc(x0 + r, y0 + r, r, color)
    disc(x1 - r, y0 + r, r, color)
    disc(x0 + r, y1 - r, r, color)
    disc(x1 - r, y1 - r, r, color)


def stroke(pts, width, color):
    hw = s(width) / 2.0
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        ax, ay, bx, by = s(ax), s(ay), s(bx), s(by)
        vx, vy = bx - ax, by - ay
        L2 = vx * vx + vy * vy
        x_lo = int(min(ax, bx) - hw) - 1
        x_hi = int(max(ax, bx) + hw) + 2
        y_lo = int(min(ay, by) - hw) - 1
        y_hi = int(max(ay, by) + hw) + 2
        for y in range(max(0, y_lo), min(IH, y_hi)):
            py = y + 0.5
            for x in range(max(0, x_lo), min(IW, x_hi)):
                px_ = x + 0.5
                t = 0.0 if L2 == 0 else ((px_ - ax) * vx + (py - ay) * vy) / L2
                t = max(0.0, min(1.0, t))
                dx, dy = px_ - (ax + t * vx), py - (ay + t * vy)
                if dx * dx + dy * dy <= hw * hw:
                    px(x, y, color)


def arc(cx, cy, r, a0, a1, width, color):
    """Clockwise-free arc from a0 to a1 degrees (screen coords, y down)."""
    hw = s(width) / 2.0
    cx, cy, r = s(cx), s(cy), s(r)
    x_lo, x_hi = int(cx - r - hw) - 1, int(cx + r + hw) + 2
    y_lo, y_hi = int(cy - r - hw) - 1, int(cy + r + hw) + 2
    for y in range(max(0, y_lo), min(IH, y_hi)):
        for x in range(max(0, x_lo), min(IW, x_hi)):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            dist = math.hypot(dx, dy)
            if abs(dist - r) > hw:
                continue
            ang = math.degrees(math.atan2(dy, dx)) % 360.0
            lo, hi = a0 % 360.0, a1 % 360.0
            inside = (lo <= ang <= hi) if lo <= hi else (ang >= lo or ang <= hi)
            if inside:
                px(x, y, color)


R = 2.3  # rim weight

# ---------------------------------------------------------------- silhouettes
disc(46, 21, 14 + R, DARK)
rrect(26 - R, 33 - R, 66 + R, 76 + R, 11, DARK)
rrect(18 - R, 38 - R, 37 + R, 70 + R, 7, DARK)
rrect(55 - R, 38 - R, 74 + R, 70 + R, 7, DARK)
rrect(28 - R, 74, 44 + R, 106, 5, DARK)
rrect(49, 74, 65 + R, 106, 5, DARK)
rrect(25 - R, 100, 48 + R, 109 + R, 4, DARK)
rrect(45, 100, 69 + R, 109 + R, 4, DARK)

# --------------------------------------------------------------------- fills
disc(46, 21, 14, GREEN)
rrect(26, 33, 66, 76, 11, GREEN)
rrect(18, 38, 37, 70, 7, GREEN)
rrect(55, 38, 74, 70, 7, GREEN)
rrect(28, 74, 44, 106, 5, GREEN)
rrect(49, 74, 65, 106, 5, GREEN)
rrect(25, 100, 48, 109, 4, GREEN)
rrect(45, 100, 69, 109, 4, GREEN)

# ------------------------------------------------------------------- details
disc(40, 17, 2.0, DARK)   # left eye
disc(52, 17, 2.0, DARK)   # right eye

arc(46, 22, 5.4, 25, 155, 1.5, DARK)   # grin

stroke([(46, 36), (40, 44)], 1.5, DARK)   # V-neck
stroke([(46, 36), (52, 44)], 1.5, DARK)
stroke([(46, 44), (46, 71)], 1.2, DARK)   # shirt seam
stroke([(29, 76), (63, 76)], 1.4, DARK)   # belt
stroke([(28, 42), (28, 68)], 1.2, DARK)   # left arm seam
stroke([(64, 42), (64, 68)], 1.2, DARK)   # right arm seam
stroke([(36, 101), (36, 108)], 1.2, DARK)  # shoe splits
stroke([(58, 101), (58, 108)], 1.2, DARK)

# ------------------------------------------------------------- down-sample --
OW, OH = int(round(W * KSCALE)), int(round(H * KSCALE))
out = bytearray(OW * OH * 4)
for oy in range(OH):
    for ox in range(OW):
        r = g = b = a = 0
        for sy in range(SS):
            yy = oy * SS + sy
            for sx in range(SS):
                xx = ox * SS + sx
                i = (yy * IW + xx) * 4
                al = buf[i + 3]
                r += buf[i] * al
                g += buf[i + 1] * al
                b += buf[i + 2] * al
                a += al
        o = (oy * OW + ox) * 4
        if a:
            out[o] = r // a
            out[o + 1] = g // a
            out[o + 2] = b // a
            out[o + 3] = a // (SS * SS)
        else:
            out[o + 3] = 0


def write_png(path, width, height, rgba):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


os.makedirs(os.path.dirname(OUT), exist_ok=True)
write_png(OUT, OW, OH, out)
print("wrote %s  %dx%d" % (OUT, OW, OH))
