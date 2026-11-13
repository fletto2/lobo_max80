#!/usr/bin/env python3
"""Run test.sh in parts at once, each with a test folder of its own.

Usage: python3 tools/testparts.py [-j N] [PART...]

test.sh is cut at its #PART lines. The lines before the first one are
the header, the settings and helpers every part needs, and the lines
from #PARTS-END on are the footer. Each part runs as the header, its
own lines and the footer, from build/parts/, with T set to
build/test/<n> and its own session log, so no two parts share a file.
The targets test.sh makes on the way are made first, so no two parts
run make on one target. The parts' output is printed in order, each
part's whole, as it would be from sh test.sh, and the exit status is 1
when any part failed. sh test.sh still runs every part in turn.

-j N runs at most N parts at once (default, the CPUs). PART numbers
pick parts, from 1, for a run of only those.
"""
import os
import subprocess
import sys
import time

PREBUILD = [['make', '-s', 'all', 'apps', '525', 'build/BOLD.FNT',
             'build/noruns/xcpmz80.sys'],
            ['make', '-s', '-C', 'c'], ['make', '-s', 'hitech'],
            ['make', '-s', 'bascom']]


def split(lines):
    """header, [(first line number, part lines)], footer"""
    marks = [i for i, l in enumerate(lines) if l.startswith('#PART')]
    if not marks or not lines[marks[-1]].startswith('#PARTS-END'):
        raise SystemExit('test.sh: no #PART lines, or no #PARTS-END last')
    head = lines[:marks[0]]
    parts = [(a + 1, lines[a:b]) for a, b in zip(marks, marks[1:])]
    return head, parts, lines[marks[-1]:]


def main():
    args = sys.argv[1:]
    jobs = os.cpu_count() or 4
    if args[:1] == ['-j']:
        jobs = int(args[1])
        args = args[2:]
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(here)
    lines = open('test.sh').read().split('\n')
    head, parts, foot = split(lines)
    cd = 'cd "$(dirname "$0")"'
    if head.count(cd) != 1:
        raise SystemExit('test.sh: the header must cd as %r once' % cd)
    head[head.index(cd)] = 'cd %s' % here
    pick = [int(a) for a in args] or list(range(1, len(parts) + 1))
    for cmd in PREBUILD:
        subprocess.call(cmd, stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL)
    os.makedirs('build/parts', exist_ok=True)
    todo = []
    for n in pick:
        first, body = parts[n - 1]
        path = 'build/parts/part%d.sh' % n
        # the part's own lines keep their line numbers in error messages
        # less the header's, which is said at the top
        open(path, 'w').write('\n'.join(
            head + ['# test.sh from line %d' % first] + body + foot) + '\n')
        todo.append((n, path))
    start = time.time()
    running, done = {}, {}
    while todo or running:
        while todo and len(running) < jobs:
            n, path = todo.pop(0)
            env = dict(os.environ, XTEST='build/test/%d' % n)
            out = open('build/parts/part%d.log' % n, 'w')
            running[n] = (subprocess.Popen(['sh', path], stdout=out,
                                           stderr=subprocess.STDOUT,
                                           stdin=subprocess.DEVNULL,
                                           env=env),
                          out, time.time())
        for n, (p, out, t) in list(running.items()):
            if p.poll() is not None:
                out.close()
                done[n] = (p.returncode, time.time() - t)
                del running[n]
        time.sleep(0.05)
    fail = 0
    for n in pick:
        sys.stdout.write(open('build/parts/part%d.log' % n).read())
        rc, secs = done[n]
        fail |= rc != 0
        sys.stderr.write('part %d: %s in %.0f s\n'
                         % (n, 'ok' if rc == 0 else 'FAIL', secs))
    sys.stderr.write('%d parts in %.0f s\n' % (len(pick), time.time() - start))
    return 1 if fail else 0


if __name__ == '__main__':
    sys.exit(main())
