#!/usr/bin/env python3
"""Make a small ZX81 .P file for ZX81.COM's tests: a REM line
holding the code at 16514, a RAND USR 16514 line, and a display file.

Usage: zx81p.py OUT.P CODE.BIN [--collapsed] [--text "ROW:TEXT"]...
       zx81p.py --rom OUT.ROM    a test ROM, no byte of a real one

--text puts upper case letters, digits and spaces on a row. The test
ROM is 8192 bytes of zeros but the shapes at 1E00h: shape N is N in
every byte, so a frame shows which code was drawn. It starts with OUT
(FDh),A, as ZX81.COM checks, and its 39 keys with SHIFT at 00A5h are
the letters A to Z over and over, made up for the tests.
"""
import struct
import sys

NEWLINE = 0x76
START = 0x407D


def zx(text):
    out = bytearray()
    for c in text:
        if c == ' ':
            out.append(0)
        elif c.isdigit():
            out.append(0x1C + int(c))
        else:
            out.append(0x26 + ord(c) - ord('A'))
    return bytes(out)


def line(num, body):
    body += bytes([NEWLINE])
    return struct.pack('>H', num) + struct.pack('<H', len(body)) + body


def make(code, collapsed, rows):
    run = bytes([0xF9, 0xD4]) + zx('16514') + bytes([0x7E, 0x8F, 1, 4, 0, 0])
    first = line(1, bytes([0xEA]) + code)
    second = line(10, run)
    nxtlin = START + len(first)
    prog = first + second
    d_file = START + len(prog)
    df = bytearray([NEWLINE])
    for r in range(24):
        text = rows.get(r, b'')
        df += text if collapsed else text.ljust(32, b'\0')
        df.append(NEWLINE)
    vars_ = d_file + len(df)
    e_line = vars_ + 1
    sv = bytearray(START - 0x4009)

    def w(addr, val):
        struct.pack_into('<H', sv, addr - 0x4009, val)
    w(0x400A, 2)
    w(0x400C, d_file)
    w(0x400E, d_file + 1)
    w(0x4010, vars_)
    w(0x4014, e_line)
    w(0x4016, e_line)
    w(0x401A, e_line + 1)
    w(0x401C, e_line + 1)
    w(0x4029, nxtlin)
    sv[0x403B - 0x4009] = 0x40
    return bytes(sv) + prog + bytes(df) + bytes([0x80])


def main():
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == '--rom':
        rom = bytearray(8192)
        for n in range(64):
            rom[0x1E00 + n * 8:0x1E00 + n * 8 + 8] = bytes([n]) * 8
        rom[0:2] = b'\xd3\xfd'
        for i in range(39):
            rom[0xA5 + i] = 0x26 + i % 26
        open(a[1], 'wb').write(rom)
        return
    if len(a) < 2:
        raise SystemExit(__doc__)
    collapsed = '--collapsed' in a
    if collapsed:
        a.remove('--collapsed')
    rows = {}
    while '--text' in a:
        i = a.index('--text')
        r, t = a[i + 1].split(':', 1)
        rows[int(r)] = zx(t)
        del a[i:i + 2]
    open(a[0], 'wb').write(make(open(a[1], 'rb').read(), collapsed, rows))


if __name__ == '__main__':
    main()
