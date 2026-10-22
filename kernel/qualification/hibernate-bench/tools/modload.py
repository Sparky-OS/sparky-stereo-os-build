#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""modload.py KMODDIR OUTDIR MODULE... : prepare modules for the bench's initramfs.

KMODDIR is a kernel's module directory (lib/modules/<release>/, as unpacked from a distribution kernel image package). For every MODULE (a name,
'-' and '_' are the same) the dependencies named in modules.dep are added, modules that are built into the kernel (modules.builtin) are skipped,
compressed modules (.xz, .gz, .zst) are decompressed (the signature that is appended to a signed module survives that), and the result is written to
OUTDIR as NN-name.ko in an order that loads dependencies first, plus OUTDIR/order (one file name per line). Needs Python 3 only (zstd through `zstd -dc`)."""
import gzip, lzma, os, re, subprocess, sys

def norm(n):
    return n.replace('-', '_')

def base(path):
    b = os.path.basename(path)
    for ext in ('.xz', '.gz', '.zst'):
        if b.endswith(ext):
            b = b[:-len(ext)]
    return norm(b[:-3] if b.endswith('.ko') else b)

def read_all(path):
    with open(path, 'rb') as f:
        data = f.read()
    if path.endswith('.xz'):
        return lzma.decompress(data)
    if path.endswith('.gz'):
        return gzip.decompress(data)
    if path.endswith('.zst'):
        return subprocess.run(['zstd', '-dc', path], check=True, capture_output=True).stdout
    return data

def main():
    kdir, out = sys.argv[1], sys.argv[2]
    wanted = [norm(m) for m in sys.argv[3:]]
    deps, path_of = {}, {}
    with open(os.path.join(kdir, 'modules.dep')) as f:
        for line in f:
            if ':' not in line:
                continue
            mod, _, rest = line.rstrip('\n').partition(':')
            name = base(mod)
            path_of[name] = mod
            deps[name] = [base(d) for d in rest.split()]
    builtin = set()
    bp = os.path.join(kdir, 'modules.builtin')
    if os.path.exists(bp):
        with open(bp) as f:
            builtin = {base(l.strip()) for l in f if l.strip()}
    need = []
    for w in wanted:
        if w in builtin:
            print('modload: %s is built into the kernel, nothing to load' % w)
            continue
        if w not in path_of:
            sys.exit('modload: module %s not found in %s/modules.dep' % (w, kdir))
        for m in deps[w] + [w]:
            if m not in need and m not in builtin:
                need.append(m)
    # a module's dependencies are a strict subset of the dependencies of anything that needs it: fewer dependencies first
    need.sort(key=lambda m: (len(deps.get(m, [])), m))
    os.makedirs(out, exist_ok=True)
    order = []
    for i, m in enumerate(need):
        fn = '%02d-%s.ko' % (i, m)
        with open(os.path.join(out, fn), 'wb') as f:
            f.write(read_all(os.path.join(kdir, path_of[m])))
        order.append(fn)
    with open(os.path.join(out, 'order'), 'w') as f:
        f.write('\n'.join(order) + ('\n' if order else ''))
    print('modload: %d module(s): %s' % (len(order), ' '.join(order)))

main()
