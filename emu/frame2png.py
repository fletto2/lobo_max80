"""Turn a frame saved by max80 -p into a PNG.

Usage: frame2png.py frame.pgm out.png [XSCALE YSCALE]

The picture is cut to the 80 x 24 text area the frame's cell comment
gives, with a border of one cell around it. Each dot is drawn XSCALE
wide and YSCALE high, 2 and 3 by default, close to the aspect the cell
comment gives, a dot about 1.5 times as high as it is wide. Python 3
only, no libraries.
"""
import struct
import sys
import zlib


def read_pgm(path):
    data = open(path, 'rb').read()
    fields = []
    cells = None
    pos = 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b'#':
            end = data.index(b'\n', pos)
            words = data[pos:end].split()
            if len(words) >= 8 and words[1] == b'cells':
                cells = [int(v) for v in words[2:8]]
            pos = end + 1
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    if fields[0] != b'P5':
        sys.exit('%s: not a PGM' % path)
    w, h, top = int(fields[1]), int(fields[2]), int(fields[3])
    pixels = data[pos + 1:pos + 1 + w * h]
    if len(pixels) != w * h:
        sys.exit('%s: short PGM' % path)
    if top != 255:
        pixels = bytes(p * 255 // top for p in pixels)
    if cells:
        x0, y0, cw, ch, cols, rows = cells
        left, top = max(0, x0 - cw), max(0, y0 - ch)
        right = min(w, x0 + (cols + 1) * cw)
        bottom = min(h, y0 + (rows + 1) * ch)
        pixels = b''.join(pixels[y * w + left:y * w + right]
                          for y in range(top, bottom))
        w, h = right - left, bottom - top
    return w, h, pixels


def chunk(kind, body):
    crc = zlib.crc32(kind + body) & 0xffffffff
    return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', crc)


def write_png(path, w, h, pixels, xs, ys):
    rows = []
    for y in range(h):
        row = pixels[y * w:(y + 1) * w]
        wide = bytes(p for p in row for _ in range(xs))
        rows.extend([b'\0' + wide] * ys)
    head = struct.pack('>IIBBBBB', w * xs, h * ys, 8, 0, 0, 0, 0)
    with open(path, 'wb') as out:
        out.write(b'\x89PNG\r\n\x1a\n')
        out.write(chunk(b'IHDR', head))
        out.write(chunk(b'IDAT', zlib.compress(b''.join(rows), 9)))
        out.write(chunk(b'IEND', b''))


def main():
    if len(sys.argv) not in (3, 5):
        sys.exit(__doc__.strip().split('\n\n')[1])
    xs, ys = (int(v) for v in sys.argv[3:5]) if len(sys.argv) == 5 else (2, 3)
    w, h, pixels = read_pgm(sys.argv[1])
    write_png(sys.argv[2], w, h, pixels, xs, ys)


if __name__ == '__main__':
    main()
