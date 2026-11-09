#!/usr/bin/env python3
"""Run the emulator with its debug sockets and type keys a program reads
without the shell's prompt in between, as WordStar and Multiplan do.
Linux only, the sockets of emu/max80 -g.

Usage: python3 tools/session.py [--machine-time] "EMULATOR ARGS" KEYS...

KEYS are typed one argument at a time, 0.3 s apart, with Python string
escapes (\\r Enter, \\x0b ^K). An argument @N waits N tenths of a second.
At the end the emulator gets SIGTERM, saves what -w and -p ask for and
prints the screen, which this prints.

The emulator runs as fast as the host allows (-t), so a wait of @N is
more than N tenths of a second of the machine's time, by as much as the
host is fast. With --machine-time an @N waits N tenths of the machine's
time, counted in CPU cycles from the debug socket, and so does the
0.3 s between keys, for a check of a program's own timing.
"""
import os
import shlex
import socket
import subprocess
import sys
import time

KBD = '/tmp/max80_kbd.sock'
REGS = '/tmp/max80.sock'
HZ = 15200000 // 3      # the CPU clock, 5.067 MHz


def cycles():
    """The CPU's cycle count, from the register dump"""
    s = socket.socket(socket.AF_UNIX)
    s.connect(REGS)
    d = b''
    while True:
        x = s.recv(4096)
        if not x:
            break
        d += x
    s.close()
    return int(d.split(b'cycles=')[1].split()[0])


def machine_wait(tenths):
    end = cycles() + tenths * HZ // 10
    while cycles() < end:
        time.sleep(0.01)


def main():
    argv = sys.argv[1:]
    machine = argv[:1] == ['--machine-time']
    if machine:
        argv = argv[1:]
    if not argv:
        raise SystemExit(__doc__)
    args = ['../emu/max80', '-K', '-g', '-T', '-t', '100000'] + shlex.split(argv[0])
    emu = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        for _ in range(200):
            if os.path.exists(KBD):
                break
            time.sleep(0.05)
        s = socket.socket(socket.AF_UNIX)
        s.connect(KBD)
        time.sleep(0.5)
        for a in argv[1:]:
            if a.startswith('@'):
                if machine:
                    machine_wait(int(a[1:]))
                else:
                    time.sleep(int(a[1:]) / 10)
                continue
            s.sendall(a.encode('latin-1').decode('unicode_escape').encode('latin-1'))
            machine_wait(3) if machine else time.sleep(0.3)
        time.sleep(1)
        s.close()
    finally:
        emu.terminate()
        out = emu.communicate()[0]
    sys.stdout.write(out.decode('latin-1'))


if __name__ == '__main__':
    main()
