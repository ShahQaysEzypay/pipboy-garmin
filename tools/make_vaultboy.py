#!/usr/bin/env python3
"""Render the Vault Boy drawable used by the Pip-Boy 3000 watch face.

Extracts and scales the classic walking Vault Boy sprite with transparent
background for Garmin Connect IQ displays (AMOLED 390x390 / 480x480).
"""
import os
import struct
import zlib

OUT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                 "resources", "drawables", "vaultboy.png")
)

def decode_png(path):
    with open(path, "rb") as f:
        data = f.read()
    idx, idat = 8, bytearray()
    w, h = 0, 0
    while idx < len(data):
        l, t = struct.unpack(">I4s", data[idx:idx+8])
        if t == b"IHDR":
            w, h = struct.unpack(">II", data[idx+8:idx+16])
        elif t == b"IDAT":
            idat.extend(data[idx+8:idx+8+l])
        elif t == b"IEND":
            break
        idx += 12 + l
    raw = zlib.decompress(bytes(idat))
    pixels = bytearray(w * h * 4)
    raw_idx = 0
    stride = w * 4
    for y in range(h):
        ft = raw[raw_idx]
        raw_idx += 1
        line = raw[raw_idx:raw_idx+stride]
        raw_idx += stride
        for x in range(stride):
            fb = line[x]
            a = pixels[y * stride + x - 4] if x >= 4 else 0
            b = pixels[(y - 1) * stride + x] if y > 0 else 0
            c = pixels[(y - 1) * stride + x - 4] if (y > 0 and x >= 4) else 0
            if ft == 0:
                v = fb
            elif ft == 1:
                v = (fb + a) & 0xff
            elif ft == 2:
                v = (fb + b) & 0xff
            elif ft == 3:
                v = (fb + ((a + b) // 2)) & 0xff
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                v = (fb + pr) & 0xff
            pixels[y * stride + x] = v
    return w, h, pixels

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

def resize_rgba(src_pix, sw, sh, dw, dh):
    dst = bytearray(dw * dh * 4)
    x_scale = sw / dw
    y_scale = sh / dh
    for dy in range(dh):
        sy = dy * y_scale
        iy = int(sy)
        fy = sy - iy
        for dx in range(dw):
            sx = dx * x_scale
            ix = int(sx)
            fx = sx - ix

            i00 = (iy * sw + ix) * 4
            i10 = (iy * sw + min(ix + 1, sw - 1)) * 4
            i01 = (min(iy + 1, sh - 1) * sw + ix) * 4
            i11 = (min(iy + 1, sh - 1) * sw + min(ix + 1, sw - 1)) * 4

            di = (dy * dw + dx) * 4
            for c in range(4):
                val = (src_pix[i00 + c] * (1 - fx) * (1 - fy) +
                       src_pix[i10 + c] * fx * (1 - fy) +
                       src_pix[i01 + c] * (1 - fx) * fy +
                       src_pix[i11 + c] * fx * fy)
                dst[di + c] = int(round(val))
    return dst

def main():
    crop_path = "/tmp/vaultboy_crop.png"
    if not os.path.exists(crop_path):
        print(f"Waiting for crop at {crop_path}")
        return
    w, h, pix = decode_png(crop_path)
    dw, dh = 77, 155
    scaled = resize_rgba(pix, w, h, dw, dh)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    write_png(OUT, dw, dh, scaled)
    print(f"wrote {OUT}  {dw}x{dh}")

if __name__ == "__main__":
    main()
