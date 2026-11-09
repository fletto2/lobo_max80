#!/usr/bin/env python3
"""Checks a frame of CLONERUN.COM's title saved by max80 -p.

Usage: check_title.py frame.pgm screen.txt [SCORE]

The frame must have 8-line cells, 80 x 24, and show the title as
clonerun.asm's tables give it: the rows of tiles of t_art, the lines of
t_text, HIGH SCORE and SCORE (0 if not given) on row 21, and every other
cell blank, dot for dot against glyphs.txt. The text rows of screen.txt
must read as the frame shows them.
"""
import os
import re
import sys

from check_frame import TOP, FCOL, read_pgm, G


def tables():
    src = open(os.path.join(TOP, 'clonerun.asm')).read()
    art = re.search(r'^t_art:\n(.*?)\tdb\t0FFh', src, re.M | re.S).group(1)
    text = re.search(r'^t_text:\n(.*?)\tdb\t0FFh', src, re.M | re.S).group(1)
    row = r'\tdb\t(\w+),(\w+),"([^"]*)",0'
    num = {'FCOL': FCOL}
    get = lambda m: (int(num.get(m[0], m[0])), int(num.get(m[1], m[1])), m[2])
    high = re.search(r'^m_high:\s+db\s+"([^"]*)"', src, re.M).group(1)
    codes = re.search(r"^t_codes:(.*?),0\n", src, re.M | re.S).group(1)
    codes = dict(re.findall(r"'(.)',(G_\w+)", codes))
    return ([get(m) for m in re.findall(row, art)],
            [get(m) for m in re.findall(row, text)], high, codes)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    score = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    font, tiles, _, _ = G.load(os.path.join(TOP, 'glyphs.txt'))
    names = {'G_BRICK': 'brick', 'G_SOLID': 'solid', 'G_LADDER': 'ladder',
             'G_GOLD': 'gold', 'G_PLAYER': 'player', 'G_GUARD': 'guard'}
    art, text, high, codes = tables()
    scr = [[0x20] * 80 for _ in range(24)]
    for r, c, s in art:
        for i, ch in enumerate(s):
            if ch in codes:
                t = tiles[names[codes[ch]]]
                scr[r][c + 2 * i], scr[r][c + 2 * i + 1] = t, t + 1
    text = text + [(21, 31, '%s%07d' % (high, score))]
    for r, c, s in text:
        for i, ch in enumerate(s):
            scr[r][c + i] = ord(ch)
    w, h, px, (x0, y0, cw, ch, cols, rows) = read_pgm(sys.argv[1])
    if (cw, ch, cols, rows) != (8, 8, 80, 24):
        raise SystemExit('cells %d x %d, %d x %d, not 8 x 8, 80 x 24' % (cw, ch, cols, rows))
    bad = []
    for r in range(24):
        for c in range(80):
            glyph = font[scr[r][c]]
            if any((px[(y0 + r * 8 + l) * w + x0 + c * 8 + d] != 0) != bool(glyph[l] >> (7 - d) & 1)
                   for l in range(8) for d in range(8)):
                bad.append((r, c))
    shown = open(sys.argv[2], encoding='utf-8').read().split('\n') + [''] * 24
    for r, c, s in text:
        if shown[r].rstrip() != ''.join(map(chr, scr[r])).rstrip():
            print('row %d reads %r' % (r, shown[r].rstrip()))
            bad.append((r, -1))
    if bad:
        print('%d cells wrong, first at row %d column %d' % (len(bad), bad[0][0], bad[0][1]))
        sys.exit(1)
    print('the title: all 1920 cells right')


if __name__ == '__main__':
    main()
