#!/usr/bin/env python3
"""S-record files for the monitor's tests.

srec.py s1 OUT ADDR LEN [SEED]   S1 lines and an S9
srec.py s2 OUT ADDR LEN [SEED]   S2 lines and an S8
srec.py bad OUT                  a good line, then a bad checksum
srec.py crc ADDR LEN [SEED]      what K should say of that data
srec.py check OUT ADDR LEN [SEED]  the file OUT, a capture of channel
                                       A, holds that data at ADDR
"""
import binascii
import random
import re
import sys


def data(n, seed):
    return random.Random(seed).randbytes(n)


def rec(typ, abytes, addr, body):
    b = bytes([abytes + len(body) + 1]) + addr.to_bytes(abytes, 'big') + body
    return 'S%d%s%02X\r\n' % (typ, b.hex().upper(), ~sum(b) & 255)


def lines(typ, abytes, addr, d, width=32):
    return ''.join(rec(typ, abytes, addr + i, d[i:i + width])
                   for i in range(0, len(d), width))


def captured(path):
    """address to byte, from every S1 or S2 line of a capture"""
    text = open(path, 'rb').read().decode('latin-1')
    mem = {}
    for m in re.finditer(r'S([12])([0-9A-F]{2})([0-9A-F]+)\r?\n', text):
        b = bytes.fromhex(m[2] + m[3])
        assert b[0] == len(b) - 1, 'count: ' + m[0]
        assert sum(b) & 255 == 255, 'checksum: ' + m[0]
        n = 2 if m[1] == '1' else 3
        a = int.from_bytes(b[1:1 + n], 'big')
        for i, v in enumerate(b[1 + n:-1]):
            mem[a + i] = v
    return mem


def main():
    a = sys.argv[1:]
    cmd = a[0]
    if cmd == 'bad':
        good = rec(1, 2, 0x4000, b'\x11\x22')
        wrong = rec(1, 2, 0x4002, b'\x33\x44')[:-4] + '00\r\n'
        more = 'D 0 10\r\n' + rec(1, 2, 0x4004, b'\x55') + 'S9030000FC\r\n'
        open(a[1], 'w', newline='').write(good + wrong + more)
    elif cmd in ('s1', 's2'):
        addr, n = int(a[2], 16), int(a[3], 16)
        d = data(n, int(a[4]) if len(a) > 4 else 1)
        if cmd == 's1':
            out = lines(1, 2, addr, d) + 'S9030000FC\r\n'
        else:
            out = lines(2, 3, addr, d) + 'S804000000FB\r\n'
        open(a[1], 'w', newline='').write(out)
    elif cmd == 'crc':
        d = data(int(a[2], 16), int(a[3]) if len(a) > 3 else 1)
        print('Sum %02Xh, CRC-16 %04Xh' % (sum(d) & 255, binascii.crc_hqx(d, 0)))
    elif cmd == 'check':
        addr, n = int(a[2], 16), int(a[3], 16)
        d = data(n, int(a[4]) if len(a) > 4 else 1)
        mem = captured(a[1])
        bad = [i for i in range(n) if mem.get(addr + i) != d[i]]
        print('%d wrong of %d' % (len(bad), n))
        sys.exit(1 if bad else 0)


main()
