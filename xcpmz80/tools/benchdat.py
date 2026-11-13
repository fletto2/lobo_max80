#!/usr/bin/env python3
"""Make BENCH.DAT, the file BENCH reads.

Usage: python3 tools/benchdat.py OUT [KB]

KB kilobytes, 64 by default, of a fixed pattern, the first 16 bytes a
tag that mkdisk.py and reilv.py set to the layout of the disk the file
goes on, such as ILV2 SKEW0 HSK0, which BENCH prints.
"""
import sys


def data(size, tag='ILV0 SKEW0 HSK0'):
    d = bytearray((i * 7 + i // 251) & 255 for i in range(size))
    d[:16] = tag.ljust(16).encode('ascii')
    return d


if __name__ == '__main__':
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    kb = int(sys.argv[2]) if len(sys.argv) == 3 else 64
    open(sys.argv[1], 'wb').write(data(kb * 1024))
