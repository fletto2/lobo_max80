#!/usr/bin/env python3
"""Make BOLD.FNT, the system's font with its two styles swapped.

Usage: python3 tools/swapfont.py src/font.bin build/BOLD.FNT

The system's font has the full face as its main style and a thin face
as its second, which Lobo's BIOS prints after ESC ). Programs that use
the second style for bold text show their bold thinner than the rest.
This font is the other way round: the thin face is the main style and
the full face the second, so that text comes out bold.

The layout is font RAM's, as tools/mkfont.py makes it: characters 20h-5Fh
at 100h-2FFh with their second style at 400h-5FFh (80h-BFh), and 60h-7Fh
at 300h-3FFh with theirs at 000h-0FFh (00h-1Fh), 8 bytes each. 7Fh, the
cursor, and its second style, 1Fh, stay where they are. The rest of the
image is copied as it is.
"""
import sys


def swap(font):
    out = bytearray(font)
    pairs = [(0x20 + i, 0x80 + i) for i in range(0x40)]       # 20h-5Fh
    pairs += [(0x60 + i, 0x00 + i) for i in range(0x1F)]      # 60h-7Eh
    for main, alt in pairs:
        a, b = main * 8, alt * 8
        out[a:a + 8], out[b:b + 8] = font[b:b + 8], font[a:a + 8]
    return bytes(out)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2])
    font = open(sys.argv[1], 'rb').read()
    if len(font) != 2048:
        sys.exit(f'{sys.argv[1]}: {len(font)} bytes, a font is 2048')
    out = swap(font)
    assert swap(out) == font
    open(sys.argv[2], 'wb').write(out)


if __name__ == '__main__':
    main()
