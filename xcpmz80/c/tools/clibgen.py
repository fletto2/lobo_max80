#!/usr/bin/env python3
"""clibgen.py: from clib/clib.lst, the resident C library's table
and the program side's thunks.

  clibgen.py LIST TAB.C THUNKDIR

TAB.C is __clib_tab, each function's address and signature, linked into
CLIB.SYS. THUNKDIR gets one .s a function, so a program links only the
thunks it calls: name: ld de,#n / ld c,#200 / jp 5.
"""
import os
import sys

LIBFN = 200


def read(path):
    fns = {}
    for ln, line in enumerate(open(path), 1):
        line = line.split('#', 1)[0].rstrip()
        if not line:
            continue
        f = line.split('\t')
        if len(f) < 3:
            sys.exit(f"{path}:{ln}: number, name and signature wanted")
        n, name, sig = int(f[0]), f[1], f[2]
        impl = f[3] if len(f) > 3 else name
        if n in fns:
            sys.exit(f"{path}:{ln}: number {n} twice")
        fns[n] = (name, sig, impl)
    return fns


def main():
    lst, tab, tdir = sys.argv[1:4]
    fns = read(lst)
    top = max(fns) + 1
    with open(tab, 'w') as o:
        o.write('/* Made by tools/clibgen.py from clib/clib.lst. */\n')
        o.write('#include "clib.h"\n\n')
        for impl in sorted({v[2] for v in fns.values()}):
            o.write(f'void {impl}(void);\n')
        # each signature once: many functions share one
        sigs = sorted({v[1] for v in fns.values()})
        sn = {sg: i for i, sg in enumerate(sigs)}
        o.write('\n')
        for sg in sigs:
            o.write(f'static const char g{sn[sg]}[] = "{sg}";\n')
        o.write(f'\nconst unsigned int __clib_n = {top};\n')
        o.write('const struct clibfn __clib_tab[] = {\n')
        for n in range(top):
            if n in fns:
                name, sig, impl = fns[n]
                o.write(f'\t{{ {impl}, g{sn[sig]} }},\t/* {n} {name} */\n')
            else:
                o.write('\t{ 0, 0 },\n')
        o.write('};\n')
    os.makedirs(tdir, exist_ok=True)
    for f in os.listdir(tdir):
        if f.endswith('.s'):
            os.remove(os.path.join(tdir, f))
    for n, (name, sig, impl) in fns.items():
        with open(os.path.join(tdir, f't{n}.s'), 'w') as o:
            o.write(f'; {name}, resident function {n}\n')
            o.write(f'\t.module\tt{n}\n\t.globl\t_{name}\n\t.area\t_CODE\n')
            o.write(f'_{name}:\n\tld\tde,#{n}\n\tld\tc,#{LIBFN}\n\tjp\t5\n')


main()
