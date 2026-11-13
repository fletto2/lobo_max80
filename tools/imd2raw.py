#!/usr/bin/env python3
"""Convert an ImageDisk .imd file to a raw sector image.

Usage: python3 tools/imd2raw.py IN.imd OUT.img

Sectors are written in cylinder, head, sector-number order. A track
whose sector numbers have a gap or a duplicate, or a sector the .imd
marks unavailable, stops it with an error and no output, since every
byte after it would be at the wrong offset or a file would hold E5
filler. convert(path, unavailable=True) writes E5 for an unavailable
sector instead, for callers that check the sectors they use.

The tracks must make one layout, as every disk here has: cylinders from
0 with none missing, the same heads on each, every track with the same
sector size, count and first sector number, none given twice.
A file cut short, or a mode, size code or sector kind out of range, is
an error too.
"""
import sys


class ImdError(ValueError):
    pass


def read_tracks(path):
    d = open(path, 'rb').read()
    try:
        i = d.index(0x1a) + 1
    except ValueError:
        raise ImdError(f'{path}: no IMD header')
    tracks = []

    def need(n, what):
        if i + n > len(d):
            raise ImdError(f'{path}: cut short in {what}')

    while i < len(d):
        need(5, 'a track header')
        mode, cyl, head, nsec, ssize = d[i:i + 5]
        if mode > 5 or ssize > 6 or head & 0x3e:
            raise ImdError(f'{path}: c{cyl}: a bad track header, mode {mode} '
                           f'head {head:02x} size code {ssize:02x}')
        i += 5
        need(nsec * (1 + (head >> 7 & 1) + (head >> 6 & 1)), f'c{cyl} h{head & 1} maps')
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
            need(1, f'c{cyl} h{head & 1} s{s}')
            kind = d[i]
            i += 1
            if kind > 8:
                raise ImdError(f'{path}: c{cyl} h{head & 1} s{s}: sector kind {kind}')
            if kind == 0:
                secs[s] = None
            elif kind % 2 == 1:
                need(size, f'c{cyl} h{head & 1} s{s}')
                secs[s] = d[i:i + size]
                i += size
            else:
                need(1, f'c{cyl} h{head & 1} s{s}')
                secs[s] = bytes([d[i]]) * size
                i += 1
        tracks.append((cyl, head & 1, size, secs))
    return tracks


def check_layout(path, tracks):
    """One layout over the disk, or later bytes move"""
    tracks = [t for t in tracks if t[3]]
    keys = [(c, h) for c, h, _, _ in tracks]
    if len(set(keys)) != len(keys):
        dup = sorted(k for k in set(keys) if keys.count(k) > 1)[0]
        raise ImdError(f'{path}: c{dup[0]} h{dup[1]} given twice')
    if not tracks:
        return
    heads = sorted({h for _, h in keys})
    cyls = sorted({c for c, _ in keys})
    for c in range(cyls[-1] + 1):
        for h in heads:
            if (c, h) not in keys:
                raise ImdError(f'{path}: c{c} h{h} missing')
    _, _, size0, secs0 = tracks[0]
    shape = (size0, len(secs0), min(secs0))
    for c, h, size, secs in tracks:
        if (size, len(secs), min(secs)) != shape:
            raise ImdError(f'{path}: c{c} h{h}: {len(secs)} x {size} from {min(secs)}, '
                           f'where c{tracks[0][0]} h{tracks[0][1]} has '
                           f'{shape[1]} x {shape[0]} from {shape[2]}')


def convert(path, unavailable=False):
    out = bytearray()
    tracks = read_tracks(path)
    check_layout(path, tracks)
    for cyl, head, size, secs in sorted(tracks, key=lambda t: t[:2]):
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
