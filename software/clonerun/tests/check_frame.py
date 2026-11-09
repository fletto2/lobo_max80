#!/usr/bin/env python3
"""Checks a frame of CLONERUN.COM or CRT.COM saved by max80 -p.

Usage: check_frame.py frame.pgm screen.txt LEVEL
       check_frame.py frame.pgm screen.txt LEVEL play [test] [paused] [revealed]
                      [men=N] [score=N] [gold=N] [COL,ROW=TILE ...]

screen.txt is what max80 -t printed for the same run. The frame must
have 8-line cells, 80 x 24, and show level LEVEL as the game draws it:
each tile in columns 12-67 and rows 4-19, row 22 LEVEL nnn and GOLD
nnn (in play SCORE, MEN and LEVEL before GOLD, the score and the lives
from score=N and men=N, 0 and 5 if not given, the gold from gold=N or
the level's), row 23 the key help from
clonerun.asm (m_paused with "paused"), and every other cell blank, dot
for dot against glyphs.txt. The levels are Lode Runner's, from
$LODERUNNER_LEVELS or private/levels.txt, as build.sh reads them.

In the viewer the starts show as figures, the hidden ladders show and a
false brick is marked. With "play" the hidden ladders and the starts
are hidden, a false brick is a brick, and the runner's figure is drawn
over the tiles, through its mask, where row 23 of the test build says
it is (X, U, Y, W, M and D), or standing at its start without "test".
The guards are drawn standing at their starts with hats on, but for the
first, drawn where row 23 of the test build says it is (from column 66,
G), and not at all when it is dead.
With "test" the levels are tests/levels_test.txt and row 23, from column
0, is taken from screen.txt, each character checked against its glyph.
Rows 22 and 23 of screen.txt must read as the frame shows them.

With "revealed" the hidden ladders show as ladders, the gold taken.
COL,ROW=TILE puts a tile of glyphs.txt, a hole crumbling or filling, or
"open" for an open hole, in place of the level's tile at that tile
column and row, before the figure is drawn over it.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(TOP, 'tools'))
import glyphs as G   # noqa: E402
import levels as L   # noqa: E402

FCOL, FROW0, FW, FH = 12, 4, 28, 16
VIEW = {' ': None, '.': None, '&': 'player', '0': 'guard', '#': 'brick', '@': 'solid',
        'H': 'ladder', '-': 'bar', '$': 'gold', 'S': 'exit', 'X': 'trap'}
PLAY = dict(VIEW, **{'&': None, '0': None, 'S': None, 'X': 'brick'})
M_STAND, M_RUN, M_CLIMB, M_HANG, M_FALL, M_DIG = range(6)
S_DEAD = 3


def read_pgm(path):
    data = open(path, 'rb').read()
    lines = data.split(b'\n', 4)
    cells = lines[1].split()
    x0, y0, cw, ch, cols, rows = (int(v) for v in cells[2:8])
    w, h = (int(v) for v in lines[2].split())
    return w, h, lines[4][:w * h], (x0, y0, cw, ch, cols, rows)


def message(label):
    src = open(os.path.join(TOP, 'clonerun.asm')).read()
    return re.search(r'^%s:\s+db\s+"([^"]*)"' % label, src, re.M).group(1)


def shape(px, py, mode, face):
    """The figure's shape, as figures.asm's shape picks it"""
    if mode == M_FALL:
        return 'fall'
    if mode == M_DIG:
        return 'dig' if face == 1 else 'digl'
    if mode == M_CLIMB:
        return 'climb%d' % (py >> 2 & 1)
    if mode == M_STAND:
        return 'stand'
    if mode == M_HANG:
        return 'hang%d' % (px >> 3 & 1)
    return ('run%d' if face == 1 else 'runl%d') % (px >> 2 & 3)


def signed(v):
    return v - 256 if v > 127 else v


def draw(out, fig, px, py):
    """A figure's 8 rows of 16 dots over the cells, as figures.asm builds it"""
    for k, row in enumerate(fig):
        m = G.mask(row)
        sx = px & 7
        f24, m24 = row << 8 >> sx, m << 8 >> sx
        sy = py + k
        r = sy >> 3
        for i in range(3):
            c = (px >> 3) + i
            if r < FH and c < 2 * FW:
                fb, mb = f24 >> (16 - 8 * i) & 255, m24 >> (16 - 8 * i) & 255
                cell = out[FROW0 + r][FCOL + c]
                cell[sy & 7] = cell[sy & 7] & ~mb & 255 | fb


def expected(level, play, test, shown, holes=(), men=5, score=0, paused=False,
             ngold=None, revealed=False):
    """The 24 rows of 80 glyphs (8 bytes each) the game should show"""
    if test:
        path = os.path.join(TOP, 'tests', 'levels_test.txt')
    else:
        path = os.environ.get('LODERUNNER_LEVELS', os.path.join(TOP, 'private', 'levels.txt'))
    lv = L.parse(path)[level - 1]
    font, tiles, _, figs = G.load(os.path.join(TOP, 'glyphs.txt'))
    scr = [[0x20] * 80 for _ in range(24)]
    guards = set(lv.guards())
    kinds = PLAY if play else VIEW
    if revealed:
        kinds = dict(kinds, S='ladder')
    for y, row in enumerate(lv.tiles()):
        for x, c in enumerate(row):
            if c == '0' and (x, y) not in guards:
                c = ' '
            t = kinds[c]
            if t:
                scr[FROW0 + y][FCOL + 2 * x] = tiles[t]
                scr[FROW0 + y][FCOL + 2 * x + 1] = tiles[t] + 1
    for x, y, t in holes:
        scr[FROW0 + y][FCOL + 2 * x] = 0x20 if t == 'open' else tiles[t]
        scr[FROW0 + y][FCOL + 2 * x + 1] = 0x20 if t == 'open' else tiles[t] + 1
    gold = 'GOLD %03d' % (len(lv.find('$')) if ngold is None else ngold)
    if play:
        top = 'SCORE %07d' % score
        top = top.ljust(16) + 'MEN %03d' % men
        top = top.ljust(27) + 'LEVEL %03d' % level
    else:
        top = 'LEVEL %03d' % level
    for i, ch in enumerate(top):
        scr[22][FCOL + i] = ord(ch)
    for i, ch in enumerate(gold):
        scr[22][FCOL + 2 * FW - len(gold) + i] = ord(ch)
    if test:
        for i, ch in enumerate(shown[23].rstrip()):
            scr[23][i] = ord(ch)
    else:
        name = ('m_paused' if paused else 'm_phelp') if play else 'm_help'
        for i, ch in enumerate(message(name)):
            scr[23][FCOL + i] = ord(ch)
    out = [[bytearray(font[c]) for c in row] for row in scr]
    if play:
        if test:
            f = shown[23].split()
            x, u, y, w, mode, face = (int(f[k], 16) for k in (1, 3, 5, 7, 9, 11))
            u, w, face = signed(u), signed(w), signed(face)
        else:
            (x, y), = lv.find('&')
            u, w, mode, face = 0, 0, M_STAND, 1
        px, py = x * 16 + u * 2, y * 8 + w
        draw(out, figs[shape(px, py, mode, face)], px, py)
        # the guards: at their starts, standing, but the first as row 23
        # shows it in the test build
        for n, (x, y) in enumerate(lv.guards()):
            u, w, mode, face, st = 0, 0, M_STAND, 1, 0
            if n == 0 and test and shown[23][66] == 'G':
                v = [int(shown[23][68 + 2 * k:70 + 2 * k], 16) for k in range(6)]
                x, u, y, w, mode, st = v
                u, w = signed(u), signed(w)
                face = -1 if mode & 0x80 else 1
                mode &= 0x7f
            if st == S_DEAD:
                continue
            px, py = x * 16 + u * 2, y * 8 + w
            draw(out, G.hat(figs[shape(px, py, mode, face)]), px, py)
    return scr, out


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    pgm, text, level = sys.argv[1], sys.argv[2], int(sys.argv[3])
    play, test = 'play' in sys.argv[4:], 'test' in sys.argv[4:]
    holes, men, score, ngold = [], 5, 0, None
    for a in sys.argv[4:]:
        if a.startswith('gold='):
            ngold = int(a[5:])
        elif a.startswith('men='):
            men = int(a[4:])
        elif a.startswith('score='):
            score = int(a[6:])
        elif '=' in a:
            xy, t = a.split('=')
            x, y = (int(v) for v in xy.split(','))
            holes.append((x, y, t))
    w, h, px, (x0, y0, cw, ch, cols, rows) = read_pgm(pgm)
    if (cw, ch, cols, rows) != (8, 8, 80, 24):
        raise SystemExit('cells %d x %d, %d x %d, not 8 x 8, 80 x 24' % (cw, ch, cols, rows))
    shown = open(text, encoding='utf-8').read().split('\n')
    shown += [''] * (24 - len(shown))
    scr, out = expected(level, play, test, [s.ljust(80) for s in shown], holes, men, score,
                        'paused' in sys.argv[4:], ngold, 'revealed' in sys.argv[4:])
    bad = []
    for r in range(24):
        for c in range(80):
            glyph = out[r][c]
            for l in range(8):
                for d in range(8):
                    lit = px[(y0 + r * 8 + l) * w + x0 + c * 8 + d] != 0
                    if lit != bool(glyph[l] >> (7 - d) & 1):
                        bad.append((r, c))
                        break
                else:
                    continue
                break
    for r in (22, 23):
        want = ''.join(map(chr, scr[r])).rstrip()
        got = shown[r].rstrip()
        if got != want:
            print('row %d reads %r, not %r' % (r, got, want))
            bad.append((r, -1))
    if bad:
        print('%d cells wrong, first at row %d column %d' % (len(bad), bad[0][0], bad[0][1]))
        sys.exit(1)
    print('level %d: all %d cells right' % (level, 24 * 80))


if __name__ == '__main__':
    main()
