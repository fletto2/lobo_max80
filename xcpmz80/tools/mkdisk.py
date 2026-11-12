#!/usr/bin/env python3
"""Make an xcpmz80 boot disk: a FAT volume with the system in its
reserved sectors.

Usage: python3 tools/mkdisk.py SYSTEM [--ds] OUT.imd [--raw OUT.img] [FILE...]
       python3 tools/mkdisk.py SYSTEM --pc KB OUT.imd [--raw OUT.img] [FILE...]
       python3 tools/mkdisk.py SYSTEM --hd MB OUT.img [FILE...]

SYSTEM is the assembled boot sector and system image. The floppy format
is read from the BPB in its first sector, the one place it is defined
(src/boot.asm). --ds makes it double sided, Lobo's sectors on both
sides of 77 cylinders, with 256 root entries.

With --hd the disk is a SASI hard disk of MB megabytes (1 to 32), a raw
image of 512-byte blocks for the emulator's -h: the same boot sector
and system, with a BPB for the hard disk, FAT16 when it has 4085
clusters or more.

--pc KB and --525 KB make a floppy of 9 x 512-byte sectors with the
same reserved sectors as the 8-inch disk. KB is 360 (5.25-inch, 40
tracks, 2 sides), 180 (one side), 720 (3.5-inch, 80 tracks), all three
for the 5-inch connector, or 1440 (3.5-inch, 80 tracks, 18 sectors) for
the 8-inch connector at 500 kbit/s.
- --525 360, --525 720 and 180 with either option are Lobo's layout:
  sectors numbered from 0 and the system from sector 0. For 360 and 720
  BPB byte 25h is set to tell the boot sector the disk has two sides.
  These boot on the MAX-80.
- --pc 360, --pc 720 and 1440 are a PC's layout, sectors numbered from
  1. The boot sector is kept at side 1 sector 1 too (sector 9), which
  the boot ROM reads when there is no sector 0, and the system follows
  it.

--ss makes a 360 or 720 one sided, the same cylinders (--525 720 --ss is
80 cylinders of one side, 360K).

--ilv N, --skew N and --hskew N set a floppy's sector order: the
interleave (default 2), the slots each cylinder is turned (default 2, 3
for 8-inch) and the slots the second side is turned more (default 0).

The FILEs are copied into the root directory, named in upper case 8.3.
`--in FOLDER` before some FILEs puts them in a folder of that name, `--in .`
returns to the root.
The IMD is for the emulator, the raw image for mtools.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'tools'))
from dmk2imd import write_imd  # noqa: E402


def bpb(boot):
    f = struct.unpack_from('<HBHBHHBHHHII', boot, 0x0b)
    return dict(bps=f[0], spc=f[1], rsvd=f[2], nfats=f[3], nroot=f[4],
                total=f[5], media=f[6], spf=f[7], spt=f[8], heads=f[9])


def hd_bpb(system, mb):
    """The boot sector of SYSTEM with a BPB for a hard disk of MB megabytes"""
    if not 1 <= mb <= 32:
        raise SystemExit('--hd: 1 to 32 megabytes')
    total = min(mb * 2048, 65504)   # whole tracks of 32: mtools checks
    p = bpb(system)
    spc = 4 if mb <= 16 else 8
    nroot = 512
    root_secs = nroot * 32 // 512
    spf = 1
    while True:
        nclus = (total - p['rsvd'] - 2 * spf - root_secs) // spc
        bits = 16 if nclus >= 4085 else 12
        if (nclus + 2) * bits // 8 + 1 <= spf * 512:
            break
        spf += 1
    boot = bytearray(system)
    struct.pack_into('<HBHBHHBHHH', boot, 0x0b, 512, spc, p['rsvd'], 2,
                     nroot, total, 0xf8, spf, 32, 1)
    boot[0x24] = 0x80
    boot[0x36:0x3e] = b'FAT16   ' if bits == 16 else b'FAT12   '
    return bytes(boot)


# KB: cylinders, heads, sectors a track, sectors a cluster, root entries,
# media byte
PC = {360: (40, 2, 9, 2, 112, 0xfd), 180: (40, 1, 9, 1, 64, 0xfc),
      720: (80, 2, 9, 2, 112, 0xf9), 1440: (80, 2, 18, 1, 224, 0xf0)}


def f5_bpb(system, kb, ss=False):
    """The boot sector of SYSTEM with a BPB for a floppy of KB, a PC's layout"""
    if kb not in PC:
        raise SystemExit('--pc: 360, 180, 720 or 1440')
    cyls, heads, spt, spc, nroot, media = PC[kb]
    if ss:                      # --ss: the same cylinders, one side
        heads, media = 1, 0xf8
    total = cyls * spt * heads
    p = bpb(system)
    spf = 1
    while (total - p['rsvd'] - 2 * spf - nroot // 16) // spc * 3 // 2 + 3 > spf * 512:
        spf += 1
    boot = bytearray(system)
    struct.pack_into('<HBHBHHBHHH', boot, 0x0b, 512, spc, p['rsvd'], 2,
                     nroot, total, media, spf, spt, heads)
    return bytes(boot)


def ds_bpb(system):
    """The boot sector of SYSTEM with a BPB for both sides of an 8-inch disk"""
    p = bpb(system)
    total, nroot = 77 * 2 * p['spt'], 256
    spf = 1
    while (total - p['rsvd'] - 2 * spf - nroot // 16) // p['spc'] * 3 // 2 + 3 > spf * 512:
        spf += 1
    boot = bytearray(system)
    struct.pack_into('<HBHBHHBHHH', boot, 0x0b, 512, p['spc'], p['rsvd'], 2,
                     nroot, total, p['media'], spf, p['spt'], 2)
    return bytes(boot)


def fat_set(fat, bits, n, v):
    if bits == 16:
        struct.pack_into('<H', fat, n * 2, v & 0xffff)
    else:
        fat12_set(fat, n, v)


def fat12_set(fat, n, v):
    i = n * 3 // 2
    if n & 1:
        fat[i] = (fat[i] & 0x0f) | (v << 4 & 0xf0)
        fat[i + 1] = v >> 4 & 0xff
    else:
        fat[i] = v & 0xff
        fat[i + 1] = (fat[i + 1] & 0xf0) | (v >> 8 & 0x0f)


def name83(path):
    base = os.path.basename(path).upper()
    stem, _, ext = base.partition('.')
    if not stem or len(stem) > 8 or len(ext) > 3:
        raise SystemExit('%s: not an 8.3 name' % path)
    return stem.ljust(8).encode() + ext.ljust(3).encode()


def build(system, files, pc=False):
    p = bpb(system)
    if p['bps'] != 512 or p['heads'] not in (1, 2):
        raise SystemExit('BPB: expected 512-byte sectors, one or two heads')
    eoc = 0xfff
    if len(system) > p['rsvd'] * 512:
        raise SystemExit('system is %d bytes, the reserved sectors hold %d'
                         % (len(system), p['rsvd'] * 512))
    disk = bytearray(p['total'] * 512)
    if pc:
        at = p['spt']   # the copy at side 1 sector 1, the system after
        if (at + 1) * 512 + len(system) - 512 > p['rsvd'] * 512:
            raise SystemExit('the system does not fit after sector %d' % at)
        disk[:512] = system[:512]
        disk[at * 512:(at + 1) * 512] = system[:512]
        disk[(at + 1) * 512:(at + 1) * 512 + len(system) - 512] = system[512:]
    else:
        disk[:len(system)] = system

    root_secs = p['nroot'] * 32 // 512
    data0 = p['rsvd'] + p['nfats'] * p['spf'] + root_secs
    nclus = (p['total'] - data0) // p['spc']
    bits = 16 if nclus >= 4085 else 12
    if bits == 16:
        eoc = 0xffff
    if (nclus + 2) * bits // 8 > p['spf'] * 512:
        raise SystemExit('BPB: %d clusters do not fit %d FAT sectors' % (nclus, p['spf']))

    fat = bytearray(p['spf'] * 512)
    fat_set(fat, bits, 0, (eoc & ~0xff) | p['media'])
    fat_set(fat, bits, 1, eoc)
    root = bytearray(root_secs * 512)
    clus = 2
    csize = p['spc'] * 512

    def alloc(data):
        """Store data in a new chain, return the first cluster."""
        nonlocal clus
        n = (len(data) + csize - 1) // csize
        if clus + n > nclus + 2:
            raise SystemExit('disk full')
        first = clus if n else 0
        for k in range(n):
            fat_set(fat, bits, clus + k, clus + k + 1 if k < n - 1 else eoc)
            off = (data0 + (clus + k - 2) * p['spc']) * 512
            chunk = data[k * csize:(k + 1) * csize]
            disk[off:off + len(chunk)] = chunk
        clus += n
        return first

    # An entry is a path for the root, or (FOLDER, path) for a folder
    # one level down. A folder's first entries are . and ..
    top = [f for f in files if isinstance(f, str)]
    folders = {}
    for f in files:
        if not isinstance(f, str):
            folders.setdefault(f[0].upper(), []).append(f[1])
    ents = []
    for path in top:
        ents.append((name83(path), 0x20, alloc(open(path, 'rb').read()),
                     os.path.getsize(path)))
    for fname, paths in folders.items():
        # the folder's own cluster comes first, so . can name it
        dclus = clus
        dsize = ((2 + len(paths)) * 32 + csize - 1) // csize * csize
        alloc(bytes(dsize))
        d = bytearray()
        d += struct.pack('<11sB10xHHHI', b'.          ', 0x10, 0, 0, dclus, 0)
        d += struct.pack('<11sB10xHHHI', b'..         ', 0x10, 0, 0, 0, 0)
        for path in paths:
            d += struct.pack('<11sB10xHHHI', name83(path), 0x20, 0, 0,
                             alloc(open(path, 'rb').read()), os.path.getsize(path))
        off = (data0 + (dclus - 2) * p['spc']) * 512
        disk[off:off + len(d)] = d
        ents.append((fname.encode('ascii').ljust(11)[:11], 0x10, dclus, 0))
    if len(ents) > p['nroot']:
        raise SystemExit('root directory full')
    for i, (nm, attr, first, size) in enumerate(ents):
        struct.pack_into('<11sB10xHHHI', root, i * 32, nm, attr, 0, 0, first, size)
    for k in range(p['nfats']):
        off = (p['rsvd'] + k * p['spf']) * 512
        disk[off:off + len(fat)] = fat
    off = (p['rsvd'] + p['nfats'] * p['spf']) * 512
    disk[off:off + len(root)] = root
    return disk, p


def folder_args(args):
    """Turn --in FOLDER markers into (FOLDER, path) entries: the files
    after one go in that folder, up to the next --in or --in ."""
    out, folder, i = [], None, 0
    while i < len(args):
        if args[i] == '--in':
            folder = None if args[i + 1] == '.' else args[i + 1]
            i += 2
            continue
        out.append(args[i] if folder is None else (folder, args[i]))
        i += 1
    return out


def stale(path):
    """True if SYSTEM is older than the src/ beside its build/ folder. A
    disk made from such a file carries an old kernel and boot sector and
    says nothing."""
    src = os.path.join(os.path.dirname(os.path.abspath(path)), '..', 'src')
    if not os.path.isfile(os.path.join(src, 'xcpmz80.asm')):
        return False
    newest = max(os.path.getmtime(os.path.join(src, f)) for f in os.listdir(src))
    return os.path.getmtime(path) < newest


def main():
    args = sys.argv[1:]
    raw = None
    if '--raw' in args:
        i = args.index('--raw')
        raw = args[i + 1]
        del args[i:i + 2]
    if len(args) < 2:
        raise SystemExit(__doc__)
    if stale(args[0]):
        raise SystemExit(f'mkdisk.py: {args[0]} is older than src/: run make first')
    if '--hd' in args:
        i = args.index('--hd')
        mb = int(args[i + 1])
        del args[i:i + 2]
        if len(args) < 2:
            raise SystemExit(__doc__)
        system = hd_bpb(open(args[0], 'rb').read(), mb)
        disk, p = build(system, folder_args(args[2:]))
        open(args[1], 'wb').write(disk)
        return
    system = open(args[0], 'rb').read()
    eight, pc = True, False
    ilv, skew, hskew = 2, None, 0
    for opt in ('--ilv', '--skew', '--hskew'):
        if opt in args:
            i = args.index(opt)
            v = int(args[i + 1])
            del args[i:i + 2]
            if opt == '--ilv':
                ilv = v
            elif opt == '--skew':
                skew = v
            else:
                hskew = v
    if '--ds' in args:
        args.remove('--ds')
        system = ds_bpb(system)
    ss = '--ss' in args
    if ss:
        args.remove('--ss')
    for opt in ('--525', '--pc'):
        if opt in args:
            i = args.index(opt)
            kb = int(args[i + 1])
            system = f5_bpb(system, kb, ss)
            del args[i:i + 2]
            eight, pc = kb == 1440, kb != 180
            if opt == '--525' and kb in (360, 720):
                if not ss:
                    system = system[:0x25] + b'\x01' + system[0x26:]
                pc = False
    if len(args) < 2:
        raise SystemExit(__doc__)
    disk, p = build(system, folder_args(args[2:]), pc)
    # The sides alternate by cylinder, as FAT counts. A PC's sectors are
    # numbered from 1, Lobo's from 0. eight: 500 kbit/s tracks.
    if skew is None:
        skew = 3 if eight else 2    # FORMAT's
    tracks = []
    base = 1 if pc else 0
    for t in range(p['total'] // p['spt']):
        cyl, head = divmod(t, p['heads'])
        secs = []
        for r in range(p['spt']):
            off = (t * p['spt'] + r) * 512
            secs.append(dict(c=cyl, h=head, r=r + base, size=512, dd=True,
                             data=bytes(disk[off:off + 512]),
                             deleted=False, bad=False))
        n = p['spt']
        slot = [None] * n   # logical sector l goes to slot l * ilv, the
        for l in range(n):  # next free one after it when that is taken
            k = l * ilv % n
            while slot[k] is not None:
                k = (k + 1) % n
            slot[k] = secs[l]
        secs = slot
        r = (cyl * skew + head * hskew) % n   # each cylinder turned by skew
        secs = secs[n - r:] + secs[:n - r]    # slots, the far side by hskew more
        tracks.append((cyl, head, secs))
    write_imd(tracks, args[1], eight, os.path.basename(args[0]))
    if raw:
        open(raw, 'wb').write(disk)


if __name__ == '__main__':
    main()
