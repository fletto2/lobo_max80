#!/usr/bin/env python3
"""Clone Runner's glyphs: checks glyphs.txt and writes the tables
the assembler includes.

Usage: glyphs.py glyphs.txt glyphs.inc

The file format is in glyphs.txt itself. The output has font1, the
codes F1LO to F1LO + F1N - 1 for font RAM 1, font2, the codes F2LO on
for font RAM 2 rows 0-7, and G_<NAME> for each tile's left half. A tile
is in font RAM 2 from 80h, or in font RAM 1 from 60h, above the text.
Codes in a range with no glyph of their own are written blank. Then figdata,
the figures' shapes, 32 bytes each: for each of the 8 rows the 16 dots
of the figure, then the 16 of its mask, high byte first. FG_<NAME> is a
shape's number. Each figure has a guard's shape too, g_NAME, the figure
with its top row widened into a hat, GFIG shapes after the player's. The mask is the figure's dots widened by one dot each
side, so a figure keeps a dark edge over a ladder or a brick. The other
tools import load().
"""
import sys

TEXT_W, TEXT_H = 5, 7
TILE_W, TILE_H = 16, 8


def rowbyte(dots, shift=0):
    """A row of # and . as a byte, the first dot bit 7, moved right
    shift dots"""
    v = 0
    for i, d in enumerate(dots):
        if d == '#':
            v |= 0x80 >> (i + shift)
    return v


def mask(row):
    """A figure row's mask: its dots widened by one each side"""
    return (row | row << 1 | row >> 1) & 0xffff


def hat(rows):
    """A guard's shape from a figure: its top row widened 2 dots each side"""
    r = rows[0]
    return [(r | r << 1 | r << 2 | r >> 1 | r >> 2) & 0xffff] + rows[1:]


def mirror(rows):
    return [int('{:016b}'.format(r)[::-1], 2) for r in rows]


def load(path):
    """Returns (glyphs, tiles, count, figs): glyphs maps code to its 8 row
    bytes, tiles maps a tile's name to its left code, count is the
    number of glyphs drawn, figs maps a figure's name to its 8 rows of 16
    dots, in the file's order. Raises ValueError on a bad file."""
    lines = open(path).read().split('\n')
    glyphs, tiles, figs, n, count = {}, {}, {}, 0, 0

    def rows(head, want_w, want_h):
        nonlocal n
        out = []
        while len(out) < want_h:
            if n >= len(lines):
                raise ValueError('%s: %s cut short' % (path, head))
            s = lines[n].rstrip()
            n += 1
            if len(s) != want_w or set(s) - {'#', '.'}:
                raise ValueError('%s line %d: %s wants %d dots of # or . a row, got %r'
                                 % (path, n, head, want_w, s))
            out.append(s)
        return out

    while n < len(lines):
        s = lines[n].strip()
        n += 1
        if not s or s.startswith(';'):
            continue
        f = s.split()
        if f[0] == 'text' and len(f) == 2:
            ch = ' ' if f[1] == 'space' else f[1]
            if len(ch) != 1 or not 0x20 <= ord(ch) < 0x7f:
                raise ValueError('%s line %d: bad character %r' % (path, n, f[1]))
            code = ord(ch)
            r = rows(s, TEXT_W, TEXT_H)
            g = bytes([rowbyte(d, 1) for d in r] + [0])
        elif f[0] == 'figure' and len(f) in (2, 4):
            if f[1] in figs:
                raise ValueError('%s line %d: figure %s twice' % (path, n, f[1]))
            if len(f) == 4:
                if f[2] != 'mirror' or f[3] not in figs:
                    raise ValueError('%s line %d: "figure NAME mirror OTHER", OTHER drawn above'
                                     % (path, n))
                figs[f[1]] = mirror(figs[f[3]])
            else:
                figs[f[1]] = [int(d.replace('#', '1').replace('.', '0'), 2)
                              for d in rows(s, TILE_W, TILE_H)]
            continue
        elif f[0] == 'tile' and len(f) == 3:
            code = int(f[2], 16)
            if not (0x80 <= code < 0xbf or 0x60 <= code < 0x7f):
                raise ValueError('%s line %d: tile code %s not in 60h-7Eh or 80h-BEh'
                                 % (path, n, f[2]))
            r = rows(s, TILE_W, TILE_H)
            if f[1] in tiles:
                raise ValueError('%s line %d: tile %s twice' % (path, n, f[1]))
            tiles[f[1]] = code
            for half in (0, 1):
                g = bytes(rowbyte(d[half * 8:half * 8 + 8]) for d in r)
                if code + half in glyphs:
                    raise ValueError('%s line %d: code %02Xh twice' % (path, n, code + half))
                glyphs[code + half] = g
                count += 1
            continue
        else:
            raise ValueError('%s line %d: not a glyph header: %r' % (path, n, s))
        if code in glyphs:
            raise ValueError('%s line %d: code %02Xh twice' % (path, n, code))
        glyphs[code] = g
        count += 1
    for name in list(figs):
        figs['g_' + name] = hat(figs[name])
    high = sorted(c for c in glyphs if c >= 0x80)
    if high != list(range(0x80, 0x80 + len(high))):
        raise ValueError('%s: the tile codes do not run up from 80h with no gaps' % path)
    return glyphs, tiles, count, figs


def table(label, glyphs, lo, hi):
    out = [label + ':']
    for c in range(lo, hi + 1):
        g = glyphs.get(c, bytes(8))
        out.append('\tdb\t' + ','.join('%03Xh' % b for b in g) + '\t; %02Xh' % c)
    return out


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    try:
        glyphs, tiles, count, figs = load(sys.argv[1])
    except ValueError as e:
        raise SystemExit('glyphs.py: %s' % e)
    low = [c for c in glyphs if c < 0x80]
    high = [c for c in glyphs if c >= 0x80]
    f1lo, f1hi = min(low), max(low)
    f2lo, f2hi = 0x80, max(high)
    out = ['; Made by tools/glyphs.py from glyphs.txt. Do not edit.',
           'NGLYPH\tequ\t%d\t\t; shapes drawn' % count,
           'F1LO\tequ\t%03Xh\t\t; font RAM 1, the first code written' % f1lo,
           'F1N\tequ\t%d\t\t; codes written' % (f1hi - f1lo + 1),
           'F2LO\tequ\t%03Xh\t\t; font RAM 2, the same' % f2lo,
           'F2N\tequ\t%d' % (f2hi - f2lo + 1)]
    for name, code in tiles.items():
        out.append('G_%s\tequ\t%03Xh' % (name.upper(), code))
    out += table('font1', glyphs, f1lo, f1hi)
    out += table('font2', glyphs, f2lo, f2hi)
    out.append('NFIG\tequ\t%d\t\t; figure shapes, the player\'s then the guards\'' % len(figs))
    out.append('GFIG\tequ\t%d\t\t; a guard\'s shape is the player\'s + GFIG' % (len(figs) // 2))
    out.append('figdata:')
    for i, (name, rows) in enumerate(figs.items()):
        out.insert(6, 'FG_%s\tequ\t%d' % (name.upper(), i))
        for r in rows:
            m = mask(r)
            out.append('\tdb\t%03Xh,%03Xh,%03Xh,%03Xh' % (r >> 8, r & 255, m >> 8, m & 255))
    open(sys.argv[2], 'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
