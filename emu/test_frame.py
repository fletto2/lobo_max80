"""Check a frame saved by max80 -p against a font file.

Usage: test_frame.py frame.pgm screen.txt font.bin [wide] [thin]
                     [skip=CHARS]

screen.txt is what max80 -t printed for the same run. Every ASCII cell
in it (21h-7Eh) must show the font's 8 rows in the frame, at the place
the frame's cell comment gives, and nothing below them. With "wide",
VLATCH bit 3 is on: the even cells show twice as wide and the odd ones
are covered by them. With "thin", a cell may also show the character in
xcpmz80's second style (25h-5Fh at 85h-BFh, 60h-7Fh at 00h-1Fh). skip=
leaves out characters the font file is known to get wrong.
"""
import sys


def read_pgm(path):
    data = open(path, 'rb').read()
    lines = data.split(b'\n', 4)
    assert lines[0] == b'P5', 'not a PGM'
    cells = lines[1].split()
    assert cells[1] == b'cells', 'no cell comment'
    x0, y0, cw, ch, cols, rows = (int(v) for v in cells[2:8])
    w, h = (int(v) for v in lines[2].split())
    pixels = lines[4][:w * h]
    assert len(pixels) == w * h, 'short PGM'
    return w, h, pixels, (x0, y0, cw, ch, cols, rows)


def main():
    pgm, text, fontpath = sys.argv[1:4]
    wide = 'wide' in sys.argv[4:]
    thin = 'thin' in sys.argv[4:]
    skip = ''.join(a[5:] for a in sys.argv[4:] if a.startswith('skip='))
    w, h, px, (x0, y0, cw, ch, cols, rows) = read_pgm(pgm)
    font = open(fontpath, 'rb').read()
    screen = open(text, encoding='utf-8').read().split('\n')[:rows]
    checked = bad = 0
    for r, line in enumerate(screen):
        for c, char in enumerate(line):
            code = ord(char)
            if not 0x21 <= code <= 0x7e or (wide and c % 2) or char in skip:
                continue
            glyphs = [font[code * 8:code * 8 + 8]]
            if thin and code >= 0x25:
                alt = code + 0x60 if code < 0x60 else code - 0x60
                at = alt * 8 if alt < 0x80 else 0x400 + (alt & 0x3f) * 8
                glyphs.append(font[at:at + 8])
            best = ch
            for glyph in glyphs:
                rows_bad = 0
                for l in range(ch):
                    want = glyph[l] if l < 8 else 0
                    y = y0 + r * ch + l
                    dots = 16 if wide else 8
                    got = 0
                    for d in range(dots):
                        x = x0 + c * cw + d
                        lit = px[y * w + x] != 0
                        bit = 7 - (d // 2 if wide else d)
                        if lit != bool(want >> bit & 1):
                            got = 1
                    rows_bad += got
                best = min(best, rows_bad)
            bad += best
            checked += 1
    print('%d cells checked, %d rows wrong, frame %dx%d' % (checked, bad, w, h))
    return 0 if checked and not bad else 1


if __name__ == '__main__':
    sys.exit(main())
