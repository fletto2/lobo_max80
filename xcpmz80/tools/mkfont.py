#!/usr/bin/env python3
"""Make xcpmz80's 2K font RAM image from unscii-8.

Usage: python3 tools/mkfont.py [--inverse] [tools/unscii-8.hex] [src/font.bin]

unscii-8, by viznut, is in the public domain. tools/unscii-8.hex is its
GNU Unifont .hex form, from http://viznut.fi/unscii/. The layout is the
MAX-80 font RAM: bytes 000h-3FFh are characters 00h-7Fh, 8 bytes each,
one byte per scan row, bit 7 the leftmost dot. 20h-7Eh are unscii's ASCII and 7Fh its medium shade, the
cursor.

The second style, which Lobo's BIOS prints after ESC ), is laid out as
Lobo's fonts lay out theirs: 80h-BFh are 20h-5Fh, and 00h-1Fh are
60h-7Fh. It is a thin face, each run of dots one shorter on the right,
so the 2-dot strokes are 1 dot and bars stay whole, as Lobo's CP/M 2.2
font has a light second style. --inverse makes it inverse video, as in
Lobo's CP/M 3 font. Rows 8-15 of 80h-BFh (bytes 600h-7FFh) are blank,
so every cell has the same dark ninth line.
"""
import sys

SHADE = 0x2592


def load_hex(src):
    """The 8x8 glyphs of a .hex font, by code point"""
    glyphs = {}
    for line in open(src):
        code, _, data = line.strip().partition(':')
        if len(data) == 16:
            glyphs[int(code, 16)] = bytes.fromhex(data)
    return glyphs


def thin_row(b):
    """A row with the rightmost dot of each run of 2 or more cleared"""
    out = b
    for x in range(7):
        here, right = 0x80 >> x, 0x80 >> (x + 1)
        if b & here and b & right and not (x < 6 and b & (0x80 >> (x + 2))):
            out &= ~right
    return out


def main():
    args = sys.argv[1:]
    inverse = '--inverse' in args
    args = [a for a in args if a != '--inverse']
    src = args[0] if args else 'tools/unscii-8.hex'
    out = args[1] if len(args) > 1 else 'src/font.bin'
    glyphs = load_hex(src)
    font = bytearray(2048)
    for ch in range(0x20, 0x7f):
        font[ch * 8:ch * 8 + 8] = glyphs[ch]
    font[0x7f * 8:0x80 * 8] = glyphs[SHADE]
    for ch in range(0x20, 0x80):
        rows = font[ch * 8:ch * 8 + 8]
        if inverse:
            alt = bytes(0xff ^ b for b in rows)
        else:
            alt = bytes(thin_row(b) for b in rows)
        if ch < 0x60:
            dst = 0x400 + (ch - 0x20) * 8
        else:
            dst = (ch - 0x60) * 8
        font[dst:dst + 8] = alt
    open(out, 'wb').write(font)


if __name__ == '__main__':
    main()
