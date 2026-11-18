#!/usr/bin/env python3
"""Render the 3 walking Vault Boy frames used by the Pip-Boy 3000 watch face."""
import math
import os
import struct
import zlib

BASE_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "resources", "drawables")
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

def warp_frame(src, cw, ch, bob_y, stride_factor, arm_shift):
    dst = bytearray(cw * ch * 4)
    for y in range(ch):
        sy_float = y + bob_y
        if sy_float > 136:
            t = (sy_float - 136.0) / float(ch - 136.0)
            t_smooth = t * t * (3.0 - 2.0 * t)
            scale_x = 1.0 - (1.0 - stride_factor) * t_smooth
        else:
            scale_x = 1.0
        for x in range(cw):
            sx_float = 46.0 + (x - 46.0) / scale_x
            if 80 <= sy_float <= 140:
                at = math.sin((sy_float - 80.0) / 60.0 * math.pi)
                sx_float -= arm_shift * at
            ix = int(sx_float)
            iy = int(sy_float)
            if 0 <= ix < cw - 1 and 0 <= iy < ch - 1:
                fx = sx_float - ix
                fy = sy_float - iy
                i00 = (iy * cw + ix) * 4
                i10 = (iy * cw + ix + 1) * 4
                i01 = ((iy + 1) * cw + ix) * 4
                i11 = ((iy + 1) * cw + ix + 1) * 4
                w00 = (1 - fx) * (1 - fy)
                w10 = fx * (1 - fy)
                w01 = (1 - fx) * fy
                w11 = fx * fy
                a_sum = src[i00+3]*w00 + src[i10+3]*w10 + src[i01+3]*w01 + src[i11+3]*w11
                oi = (y * cw + x) * 4
                if a_sum > 64:
                    for c in range(3):
                        v = (src[i00+c]*src[i00+3]*w00 + src[i10+c]*src[i10+3]*w10 +
                             src[i01+c]*src[i01+3]*w01 + src[i11+c]*src[i11+3]*w11) / a_sum
                        dst[oi+c] = int(round(v))
                    dst[oi+3] = int(round(a_sum))
    return dst

def main():
    for i in range(8):
        for fname in (("vaultboy.png" if i == 0 else f"vaultboy{i}.png"), f"vaultboy_run{i}.png"):
            p = os.path.join(BASE_DIR, fname)
            if os.path.exists(p):
                w, h, _ = decode_png(p)
                print(f"verified {p} ({w}x{h})")

if __name__ == "__main__":
    main()
