#!/usr/bin/env python3
"""Clone Runner's levels: reads Lode Runner's stages and writes the
tables the assembler includes.

Usage: levels.py LEVELS.TXT [levels.inc]

Without an output file it only checks. Exits 1 with the level and line
on the first fault.

The file is the C64 decode of Lode Runner's 150 stages, or a file of
test levels in the same form: lines starting with # before the first
level, then each level as a line "=== NNN ===" and 16 rows of 28
characters. A row may be short, the rest empty. The characters:

  space or .  empty          X  false brick (looks like brick, is empty)
  #  brick, can be dug       S  hidden ladder (shows when the gold is gone)
  @  solid block             $  gold
  H  ladder                  0  a guard's start, on an empty tile
  -  bar                     &  the runner's start, on an empty tile

Each level needs one runner start. As the C64 does at load, at most 5
guards and 45 hidden ladders are kept, scanning bottom-up and right to
left, and the rest are blanked.

Each level packs as the gold, the runner's column and row, the number of
guards, a column and row for each guard, then the 448 tiles at 3 bits,
row by row, 8 tiles in 3 bytes, the first tile in the top bits: 168
bytes. The kinds' numbers are the game's (actors.asm, T_*).
"""
import sys

W, H = 28, 16
MAXGUARD = 5
MAXHLADDER = 45
KINDS = {' ': 0, '.': 0, '#': 1, '@': 2, 'H': 3, '-': 4, 'X': 5, 'S': 6, '$': 7,
         '0': 0, '&': 0}


class LevelError(ValueError):
    pass


class Level:
    def __init__(self, number, rows, line):
        self.number, self.rows, self.line = number, rows, line

    def find(self, ch):
        return [(x, y) for y, r in enumerate(self.rows) for x, c in enumerate(r) if c == ch]

    def guards(self):
        """The guard starts kept, in the C64's load order"""
        return sorted(self.find('0'), key=lambda p: (-p[1], -p[0]))[:MAXGUARD]

    def tiles(self):
        """The rows as the game loads them: the hidden ladders past the
        45th blanked"""
        keep = set(sorted(self.find('S'), key=lambda p: (-p[1], -p[0]))[:MAXHLADDER])
        return [''.join(' ' if c == 'S' and (x, y) not in keep else c for x, c in enumerate(r))
                for y, r in enumerate(self.rows)]


def parse(path):
    levels, cur, n = [], None, 0
    for n, raw in enumerate(open(path).read().split('\n'), 1):
        s = raw.rstrip('\r')
        if s.startswith('==='):
            f = s.split()
            if len(f) != 3 or f[2] != '===' or not f[1].isdigit():
                raise LevelError('%s line %d: a level starts "=== NNN ==="' % (path, n))
            if cur:
                levels.append(finish(cur, path))
            if int(f[1]) != len(levels) + 1:
                raise LevelError('%s line %d: level %s, %d wanted' % (path, n, f[1], len(levels) + 1))
            cur = [int(f[1]), [], n]
            continue
        if cur is None:
            if s and not s.startswith('#'):
                raise LevelError('%s line %d: a row before the first level' % (path, n))
            continue
        if len(cur[1]) == H:
            if s.strip():
                raise LevelError('%s line %d: level %d has more than %d rows' % (path, n, cur[0], H))
            continue
        if len(s) > W:
            raise LevelError('%s line %d: level %d row %d is %d tiles wide, %d at most'
                             % (path, n, cur[0], len(cur[1]), len(s), W))
        bad = set(s) - set(KINDS)
        if bad:
            raise LevelError('%s line %d: level %d, not a tile: %s'
                             % (path, n, cur[0], ' '.join(sorted(repr(c) for c in bad))))
        cur[1].append(s.ljust(W))
    if cur:
        levels.append(finish(cur, path))
    if not levels:
        raise LevelError('%s: no levels' % path)
    if len(levels) > 255:
        raise LevelError('%s: %d levels, 255 at most' % (path, len(levels)))
    return levels


def finish(cur, path):
    number, rows, line = cur
    where = '%s level %d (line %d)' % (path, number, line)
    if len(rows) != H:
        raise LevelError('%s: %d rows, not %d' % (where, len(rows), H))
    lv = Level(number, rows, line)
    if len(lv.find('&')) != 1:
        raise LevelError('%s: %d runner starts, 1 wanted' % (where, len(lv.find('&'))))
    if len(lv.find('$')) > 255:
        raise LevelError('%s: %d pieces of gold, 255 at most' % (where, len(lv.find('$'))))
    return lv


def pack(rows):
    bits = ''.join('{:03b}'.format(KINDS[c]) for r in rows for c in r)
    return bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))


def write(levels, path, source):
    out = ['; Made by tools/levels.py from %s. Do not edit, do not commit.' % source,
           'NLEVELS\tequ\t%d' % len(levels),
           'levtab:']
    for lv in levels:
        out.append('\tdw\tlev_%d' % lv.number)
    for lv in levels:
        (px, py), guards = lv.find('&')[0], lv.guards()
        out.append('lev_%d:\tdb\t%d,%d,%d,%d\t; gold, runner column and row, guards'
                   % (lv.number, len(lv.find('$')), px, py, len(guards)))
        for gx, gy in guards:
            out.append('\tdb\t%d,%d' % (gx, gy))
        data = pack(lv.tiles())
        for i in range(0, len(data), 12):
            out.append('\tdb\t' + ','.join('%03Xh' % b for b in data[i:i + 12]))
    open(path, 'w').write('\n'.join(out) + '\n')


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    try:
        levels = parse(sys.argv[1])
    except (LevelError, OSError) as e:
        print('levels.py: %s' % e, file=sys.stderr)
        sys.exit(1)
    if len(sys.argv) == 3:
        write(levels, sys.argv[2], sys.argv[1])


if __name__ == '__main__':
    main()
