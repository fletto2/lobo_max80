#!/usr/bin/env python3
"""Convert an ImageDisk .imd file to a raw sector image.

Usage: python3 tools/imd2raw.py IN.imd OUT.img

Sectors are written in cylinder, head, sector-number order. A sector the
.imd marks unavailable is written as E5 filler and reported.
"""
import sys


def read_tracks(path):
    d = open(path, 'rb').read()
    i = d.index(0x1a) + 1
    tracks = []
    while i < len(d):
        mode, cyl, head, nsec, ssize = d[i:i + 5]
        i += 5
        smap = list(d[i:i + nsec])
        i += nsec
        if head & 0x80:
            i += nsec
        if head & 0x40:
            i += nsec
        size = 128 << ssize
        secs = {}
        for s in smap:
            kind = d[i]
            i += 1
            if kind == 0:
                secs[s] = None
            elif kind % 2 == 1:
                secs[s] = d[i:i + size]
                i += size
            else:
                secs[s] = bytes([d[i]]) * size
                i += 1
        tracks.append((cyl, head & 1, size, secs))
    return tracks


def convert(path):
    out = bytearray()
    for cyl, head, size, secs in sorted(read_tracks(path), key=lambda t: t[:2]):
        for s in sorted(secs):
            if secs[s] is None:
                print(f'{path}: c{cyl} h{head} s{s} unavailable', file=sys.stderr)
            out += secs[s] or b'\xe5' * size
    return bytes(out)


if __name__ == '__main__':
    with open(sys.argv[2], 'wb') as f:
        f.write(convert(sys.argv[1]))
