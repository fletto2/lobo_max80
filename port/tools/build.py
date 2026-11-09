#!/usr/bin/env python3
"""Build TETRIS.COM from our source and your own Tetris.gb.

Usage: python3 port/tools/build.py ROM

ROM is your own copy of the Game Boy Tetris cartridge, retail DMG-TRA-1
(World, Rev A), checked by SHA1. The game's numbers are lifted from it
into port/src/tables.asm, which git ignores: Nintendo's bytes stay on
your machine. Then sjasmplus assembles port/src/ and the program goes
on boot disks for the emulator, which take TETRIS at the prompt:

  port/build/TETRIS.COM
  port/build/tetris.imd      emu/max80 -a port/build/tetris.imd
  port/build/tetris_525.imd  emu/max80 -D 1 -a port/build/tetris_525.imd
  port/build/tetris_180.imd  emu/max80 -D 1 -a port/build/tetris_180.imd

tetris_525.imd and tetris_180.imd are xcpmz80 for a 5.25-inch drive,
360K double sided and 180K single sided. sjasmplus is $SJASMPLUS, or
sjasmplus on the PATH. It crashes on a UNC path, so the sources are
assembled in a local scratch directory. The disks need xcpmz80's make.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

PORT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(PORT)
SRC = os.path.join(PORT, 'src')
BUILD = os.path.join(PORT, 'build')

ROM_SHA1 = '74591cc9501af93873f9a5d3eb12da12c0723bbc'


def sjasmplus():
    if os.environ.get('SJASMPLUS'):
        return os.environ['SJASMPLUS']
    win = os.path.join(ROOT, 'tools', 'sjasmplus-1.24.0.win', 'sjasmplus.exe')
    if os.name == 'nt' and os.path.exists(win):
        return win
    found = shutil.which('sjasmplus')
    if not found:
        raise SystemExit('sjasmplus not found: set SJASMPLUS or put it on the PATH')
    return found


# The addresses in the ROM of the numbers the port uses
SPEEDS = 0x1B06         # SetNumFramesUntilPiecesMoveDown .framesData, 21 bytes
SPAWN_Y = 0x200D        # ld [hl],$18 at 0x200D: the spawn Y, then X at 0x2010
SPAWN_X = 0x2010
WELL_LEFT = 0x214E      # ld hl,$C842: the line check's row 2, column 2
PIECES = 0x2B64         # the sprite script table, by piece code
SCORES = (0x1FA6, 0x1FAE, 0x1FB6, 0x1FBD)  # ld de,nnnn: 1 to 4 lines, BCD
DAS = {                 # InGameCheckButtonsPressed's ld a,n, right then left
    'DASINIT': (0x2517, 0x254E),        # a press, or neither held
    'DASREP': (0x2525, 0x255C),         # the repeat
    'DASBLK': (0x2547,),                # a blocked move
}
NCODES = 28             # 7 ids x 4 rotations


def word(rom, a):
    return rom[a] | rom[a + 1] << 8


def expect(rom, a, op, what):
    if rom[a] != op:
        raise SystemExit('ROM %04X: not %s' % (a, what))
    return rom[a + 1]


def pieces(rom):
    """For each piece code, its 4 cells as (row, column) in its 4x4
    grid, and the grid's top left on the board at the spawn place."""
    out, base = [], None
    for code in range(NCODES):
        rec = word(rom, PIECES + 2 * code)
        stream = word(rom, rec)
        offset = (rom[rec + 2], rom[rec + 3])   # to $FF90, $FF91
        if base not in (None, offset):
            raise SystemExit('piece %d: other base offsets' % code)
        base = offset
        coords = word(rom, stream)
        cells, a, n = [], stream + 2, 0
        while rom[a] != 0xFF:
            if rom[a] != 0xFE:                  # $FE an empty cell
                y, x = rom[coords + 2 * n], rom[coords + 2 * n + 1]
                cells.append((y // 8, x // 8))
            a += 1
            n += 1
        if len(cells) != 4 or n > 16:
            raise SystemExit('piece %d: not 4 cells in a 4x4 grid' % code)
        out.append(cells)
    # The sprite engine (0x2AFA-0x2B34) puts a cell at Y + $FF90 + its y,
    # X + $FF91 + its x, and GetScreen0AddressOfPieceSquare (0x29E3) maps
    # that to screen row (Y - $10) / 8, column (X - 8) / 8
    y = expect(rom, SPAWN_Y, 0x36, 'the spawn Y')
    x = expect(rom, SPAWN_X, 0x36, 'the spawn X')
    left = expect(rom, WELL_LEFT, 0x21, 'the line check') & 0x1F
    row = (((base[0] + y) & 0xFF) - 0x10) // 8
    col = (((base[1] + x) & 0xFF) - 8) // 8 - left
    return out, row, col


def tables(rom):
    """The lines of tables.asm"""
    cells, row, col = pieces(rom)
    lines = [
        '; Lifted from your own Tetris.gb by port/tools/build.py.',
        '; Generated, gitignored, never committed: the values are Nintendo\'s.',
        '',
        '; Frames a row less one, by level (0x%04X)' % SPEEDS,
        'speeds:\tdb\t' + ','.join('%d' % b for b in rom[SPEEDS:SPEEDS + 21]),
        '',
        '; The board row and column of a piece grid\'s top left at the spawn',
        'SPAWNR\tequ\t%d' % row,
        'SPAWNC\tequ\t%d' % col,
        '',
        '; Each piece code\'s 4 cells, row and column in its grid (0x%04X)' % PIECES,
        'pcells:',
    ]
    for code, c in enumerate(cells):
        lines.append('\tdb\t' + ', '.join('%d,%d' % rc for rc in c) + '\t; %d' % code)
    pts = []
    for a in SCORES:
        expect(rom, a, 0x11, 'ld de,nnnn')
        bcd = '%04X' % word(rom, a + 1)
        if not bcd.isdigit():
            raise SystemExit('ROM %04X: not BCD' % a)
        pts.append(bcd.lstrip('0') or '0')
    lines += ['', '; Points for 1 to 4 lines, from BCD (0x1F91)',
              'scores:\tdw\t' + ','.join(pts)]
    lines += ['', '; The sideways auto repeat, frames (0x2509-0x2571)']
    for name, at in DAS.items():
        vals = {expect(rom, a, 0x3E, 'ld a,n') for a in at}
        if len(vals) != 1:
            raise SystemExit('%s: right and left differ' % name)
        lines.append('%s\tequ\t%d' % (name, vals.pop()))
    return lines


def lift(path):
    """Checks the ROM and writes tables.asm from it"""
    rom = open(path, 'rb').read()
    if hashlib.sha1(rom).hexdigest() != ROM_SHA1:
        raise SystemExit('%s: not the Tetris this port reads (SHA1 %s)'
                         % (path, ROM_SHA1.upper()))
    with open(os.path.join(SRC, 'tables.asm'), 'w', newline='\n') as f:
        f.write('\n'.join(tables(rom)) + '\n')


def assemble(com, defines=()):
    """Assembles port/src/ into com, with these sjasmplus defines, such
    as TEST or LEVEL=9"""
    with tempfile.TemporaryDirectory() as tmp:
        for name in os.listdir(SRC):
            if name.endswith(('.asm', '.inc')):
                shutil.copy(os.path.join(SRC, name), tmp)
        subprocess.run([sjasmplus(), '--nologo', '--msg=war', '--lst=tetris.lst',
                        '--raw=TETRIS.COM'] + ['-D' + d for d in defines] + ['tetris.asm'],
                       check=True, cwd=tmp)
        shutil.copyfile(os.path.join(tmp, 'TETRIS.COM'), com)
        if not defines:
            shutil.copyfile(os.path.join(tmp, 'tetris.lst'), os.path.join(BUILD, 'tetris.lst'))


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    lift(sys.argv[1])
    os.makedirs(BUILD, exist_ok=True)
    com = os.path.join(BUILD, 'TETRIS.COM')
    assemble(com)
    imd = os.path.join(BUILD, 'tetris.imd')
    xcpm = os.path.join(ROOT, 'xcpmz80')
    subprocess.run(['make', '-s', 'build/xcpmz80.sys'], cwd=xcpm, check=True)
    # On an 8-inch xcpmz80 boot disk
    subprocess.run([sys.executable, '-I', os.path.join(xcpm, 'tools', 'mkdisk.py'),
                    os.path.join(xcpm, 'build', 'xcpmz80.sys'), imd, com],
                   check=True, stdout=subprocess.DEVNULL)
    imd525 = os.path.join(BUILD, 'tetris_525.imd')
    subprocess.run([sys.executable, '-I', os.path.join(xcpm, 'tools', 'mkdisk.py'),
                    os.path.join(xcpm, 'build', 'xcpmz80.sys'), '--525', '360', imd525, com],
                   check=True, stdout=subprocess.DEVNULL)
    imd180 = os.path.join(BUILD, 'tetris_180.imd')
    subprocess.run([sys.executable, '-I', os.path.join(xcpm, 'tools', 'mkdisk.py'),
                    os.path.join(xcpm, 'build', 'xcpmz80.sys'), '--525', '180', imd180, com],
                   check=True, stdout=subprocess.DEVNULL)
    print('%s, %d bytes, on %s, %s and %s' % (os.path.relpath(com, ROOT), os.path.getsize(com),
                                              os.path.relpath(imd, ROOT),
                                              os.path.relpath(imd525, ROOT),
                                              os.path.relpath(imd180, ROOT)))


if __name__ == '__main__':
    main()
