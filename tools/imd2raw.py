#!/usr/bin/env python3
"""Convert an ImageDisk .imd file to a raw sector image.

Usage: python3 tools/imd2raw.py IN.imd OUT.img

Sectors are written in cylinder, head, sector-number order. A track
whose sector numbers have a gap or a duplicate, or a sector the .imd
marks unavailable, stops it with an error and no output, since every
byte after it would be at the wrong offset or a file would hold E5
filler. convert(path, unavailable=True) writes E5 for an unavailable
sector instead, for callers that check the sectors they use.
"""
import sys


class ImdError(ValueError):
    pass


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
        if len(set(smap)) != len(smap):
            raise ImdError(f'{path}: c{cyl} h{head & 1}: a sector number twice: {smap}')
        if smap and sorted(smap) != list(range(min(smap), min(smap) + nsec)):
            raise ImdError(f'{path}: c{cyl} h{head & 1}: sector numbers with a gap: {sorted(smap)}')
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


def convert(path, unavailable=False):
    out = bytearray()
    for cyl, head, size, secs in sorted(read_tracks(path), key=lambda t: t[:2]):
        for s in sorted(secs):
            if secs[s] is None:
                if not unavailable:
                    raise ImdError(f'{path}: c{cyl} h{head} s{s} unavailable')
                print(f'{path}: c{cyl} h{head} s{s} unavailable, E5 written', file=sys.stderr)
            out += secs[s] or b'\xe5' * size
    return bytes(out)


if __name__ == '__main__':
    try:
        data = convert(sys.argv[1])
    except ImdError as e:
        sys.exit(f'imd2raw: {e}')
    with open(sys.argv[2], 'wb') as f:
        f.write(data)
