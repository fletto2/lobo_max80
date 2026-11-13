#!/usr/bin/env python3
"""Run the emulator with its debug sockets and type keys a program reads
without the shell's prompt in between, as WordStar and Multiplan do.
Linux only, the sockets of emu/max80 -g.

Usage: python3 tools/session.py [--host-time] "EMULATOR ARGS" KEYS...

KEYS are typed one argument at a time, 0.3 s apart, with Python string
escapes (\\r Enter, \\x0b ^K). An argument @N waits N tenths of a
second. @?TEXT waits until the last line with text on it ends with
TEXT, as a prompt does, and @/TEXT until TEXT shows anywhere on the
screen, both once the screen has changed since the last key was typed,
each at most LIMIT seconds of the host's (60, or
$SESSION_LIMIT): it then says so on stderr, and in the file
$SESSION_LOG names when there is one, goes on, and this exits 3.
Before the first key it waits for the shell's prompt, A:\\> or A>, at
most 20 seconds of the machine's. At the end the emulator gets SIGTERM,
saves what -w and -p ask for and prints the screen, which this prints.

Times are the machine's, counted in CPU cycles from the debug socket,
while the emulator runs as fast as the host allows (-t), so a wait
costs the host little and does not depend on how busy it is. With
--host-time they are the host's, as they were.

The emulator runs as instance s<pid> (its -N), its sockets its own, so
two sessions or two suites can run at once. MAX80_INSTANCE names
another instance.
"""
import os
import shlex
import socket
import subprocess
import sys
import time

INST = os.environ.get('MAX80_INSTANCE') or 's%d' % os.getpid()
KBD = '/tmp/max80_kbd_%s.sock' % INST
REGS = '/tmp/max80_%s.sock' % INST
MEM = '/tmp/max80_mem_%s.sock' % INST
HZ = 15200000 // 3      # the CPU clock, 5.067 MHz
LIMIT = float(os.environ.get('SESSION_LIMIT') or 60)
PROMPTS = ('A:\\>', 'A>')


def ask(path, msg=b''):
    s = socket.socket(socket.AF_UNIX)
    s.connect(path)
    if msg:
        s.sendall(msg)
    d = b''
    while True:
        x = s.recv(65536)
        if not x:
            break
        d += x
    s.close()
    return d


def cycles():
    """The CPU's cycle count, from the register dump"""
    return int(ask(REGS).split(b'cycles=')[1].split()[0])


def screen():
    """The screen as text, as the emulator prints it"""
    return ask(MEM, b'screen').decode('utf-8', 'replace')


def shows(text, anywhere, before=None):
    """text on the screen, or at the end of its last line with text,
    and the screen not what it was before"""
    s = screen()
    if s == before:
        return False
    if anywhere:
        return text in s
    lines = [l.rstrip() for l in s.splitlines() if l.strip()]
    return bool(lines) and lines[-1].endswith(text.rstrip())


def machine_wait(tenths):
    end = cycles() + tenths * HZ // 10
    while cycles() < end:
        time.sleep(0.005)


def text_wait(texts, host_limit, machine_limit=None, anywhere=False,
              before=None):
    """Until one of texts shows; False at a limit"""
    end = time.time() + host_limit
    mend = cycles() + machine_limit * HZ // 10 if machine_limit else None
    while True:
        if any(shows(t, anywhere, before) for t in texts):
            return True
        if time.time() > end or (mend and cycles() > mend):
            return False
        time.sleep(0.005)


def main():
    argv = sys.argv[1:]
    host = argv[:1] == ['--host-time']
    if argv[:1] in (['--host-time'], ['--machine-time']):
        argv = argv[1:]
    if not argv:
        raise SystemExit(__doc__)
    args = (['../emu/max80', '-K', '-g', '-N', INST, '-T', '-t', '100000']
            + shlex.split(argv[0]))
    emu = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    wait = (lambda n: time.sleep(n / 10)) if host else machine_wait
    status = 0
    before = None
    try:
        for _ in range(200):
            if all(os.path.exists(p) for p in (KBD, REGS, MEM)):
                break
            time.sleep(0.05)
        s = socket.socket(socket.AF_UNIX)
        s.connect(KBD)
        if host:
            time.sleep(0.5)
        else:
            text_wait(PROMPTS, LIMIT, 200)
        for a in argv[1:]:
            if a[:2] in ('@?', '@/'):
                if not text_wait([a[2:]], LIMIT, anywhere=a[1] == '/',
                                 before=before):
                    msg = 'session.py: no %r on the screen\n' % a[2:]
                    sys.stderr.write(msg)
                    if os.environ.get('SESSION_LOG'):
                        with open(os.environ['SESSION_LOG'], 'a') as f:
                            f.write(msg)
                    status = 3
                continue
            if a.startswith('@'):
                wait(int(a[1:]))
                continue
            before = screen()
            s.sendall(a.encode('latin-1').decode('unicode_escape').encode('latin-1'))
            wait(3)
        wait(10)
        s.close()
    finally:
        emu.terminate()
        out = emu.communicate()[0]
    sys.stdout.write(out.decode('latin-1'))
    return status


if __name__ == '__main__':
    sys.exit(main())
