#!/usr/bin/env python3
"""Convert a DMK floppy image to an ImageDisk .imd file.

Usage: python3 tools/dmk2imd.py IN.dmk OUT.imd [--eight]

DMK keeps each raw track behind a table of 64 ID address mark pointers.
Bit 15 of a pointer is set for a double-density ID, the low 14 bits are
the offset of the FEh byte from the track start, table included. Single
density bytes are stored twice unless header byte 4 bit 6 says the disk
is single density only. Each ID gives cylinder, head, sector and size
code, and its data field is the next F8h-FBh mark (F8h, F9h deleted)
within 64 bytes. The CRCs are checked, and a bad one is reported and the
sector kept with the IMD data-error mark.

DMK has no data rate. The IMD modes are 5-inch (250 kbit/s) unless
--eight is given. A track whose sectors differ in size cannot be stored
in IMD and stops the conversion.
"""
import sys
import time


def crc16(data, crc=0xffff):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = (crc << 1 ^ 0x1021 if crc & 0x8000 else crc << 1) & 0xffff
    return crc


def read_dmk(path):
    d = open(path, 'rb').read()
    ntracks, tlen, flags = d[1], d[2] | d[3] << 8, d[4]
    sides = 1 if flags & 0x10 else 2
    sd_once = bool(flags & 0x40)
    tracks, problems = [], []
    for t in range(ntracks * sides):
        base = 16 + t * tlen
        trk = d[base:base + tlen]
        cyl, head = divmod(t, sides) if sides == 2 else (t, 0)
        secs = []
        for e in range(64):
            ptr = trk[e * 2] | trk[e * 2 + 1] << 8
            if not ptr:
                break
            dd, off = bool(ptr & 0x8000), ptr & 0x3fff
            step = 1 if dd or sd_once else 2

            def at(k, off=off, step=step):
                return trk[off + k * step]

            if at(0) != 0xfe:
                problems.append('track %d entry %d: no FEh at the pointer' % (t, e))
                continue
            idf = [at(k) for k in range(5)]
            crc = at(5) << 8 | at(6)
            pre = [0xa1] * 3 if dd else []
            id_ok = crc16(pre + idf) == crc
            c, h, r, n = idf[1:5]
            size = 128 << (n & 3)
            k = 7
            while k < 7 + 64 and not 0xf8 <= at(k) <= 0xfb:
                k += 1
            if k >= 7 + 64:
                problems.append('C%d H%d R%d: no data mark' % (c, h, r))
                continue
            mark = at(k)
            data = bytes(at(k + 1 + i) for i in range(size))
            dcrc = at(k + 1 + size) << 8 | at(k + 2 + size)
            data_ok = crc16(pre + [mark] + list(data)) == dcrc
            if not (id_ok and data_ok):
                problems.append('C%d H%d R%d: bad %s CRC' % (c, h, r, 'ID' if not id_ok else 'data'))
            secs.append(dict(c=c, h=h, r=r, size=size, dd=dd, data=data,
                             deleted=mark in (0xf8, 0xf9), bad=not (id_ok and data_ok)))
        tracks.append((cyl, head, secs))
    return tracks, problems


def write_imd(tracks, path, eight, source, tool='tools/dmk2imd.py', stamp=None):
    out = bytearray(time.strftime('IMD 1.18: %d/%m/%Y %H:%M:%S\r\n', stamp or time.localtime()).encode())
    out += ('Converted from %s by %s\r\n' % (source, tool)).encode() + b'\x1a'
    for cyl, head, secs in tracks:
        if not secs:
            continue
        sizes = {s['size'] for s in secs}
        if len(sizes) > 1:
            raise SystemExit('cylinder %d head %d: mixed sector sizes' % (cyl, head))
        size = sizes.pop()
        mfm = secs[0]['dd']
        mode = (3 if mfm else 0) + (0 if eight else 2)
        cmap = any(s['c'] != cyl for s in secs)
        hmap = any(s['h'] != head for s in secs)
        out += bytes([mode, cyl, head | (0x80 if cmap else 0) | (0x40 if hmap else 0),
                      len(secs), size.bit_length() - 8])
        out += bytes(s['r'] for s in secs)
        if cmap:
            out += bytes(s['c'] for s in secs)
        if hmap:
            out += bytes(s['h'] for s in secs)
        for s in secs:
            same = len(set(s['data'])) == 1
            out.append((2 if same else 1) + (2 if s['deleted'] else 0) + (4 if s['bad'] else 0))
            out += s['data'][:1] if same else s['data']
    open(path, 'wb').write(out)


def main():
    args = [a for a in sys.argv[1:] if a != '--eight']
    if len(args) != 2:
        raise SystemExit(__doc__)
    tracks, problems = read_dmk(args[0])
    write_imd(tracks, args[1], '--eight' in sys.argv, args[0].rsplit('/', 1)[-1])
    nsec = sum(len(s) for _, _, s in tracks)
    print('%d tracks, %d sectors, %d problems' % (len(tracks), nsec, len(problems)))
    for p in problems:
        print('  ' + p)


if __name__ == '__main__':
    main()
