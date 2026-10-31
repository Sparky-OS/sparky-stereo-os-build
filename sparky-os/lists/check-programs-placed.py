#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# Every program the edition's repository publishes (a package with a desktop entry) must have a place:
# the image (image.list, or apps.list outside the role tasks), a role task (roles.tsv), one of the other
# lists, or an integration. On 2026-10-31 our browser, Marble and the KDAB demonstrator were in the
# repository and in no list, so no image or task installed them (Daniel: "are you kidding we're not
# shipping our stereo software?").
# Usage: check-programs-placed.py [--metas <make-meta.py output dir>] [--image <the image's dpkg -l>] <repository Contents files>...
# Placed: what the image installs (its dpkg -l, dependencies included), the KDE edition's base names, what any meta or
# task names, the lists, roles.tsv, integrations.tsv, and
# not-on-image.tsv (left out on purpose, with the reason).
import gzip, lzma, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
LISTS = ['image', 'apps', 'games', 'gaming', 'film', 'emulation-3d', 'hardware', 'hardware-found', 'system',
         'look', 'runtimes', 'languages', 'developer', 'os-developer', 'aptus']

def read_list(name):
    path = os.path.join(HERE, name + '.list')
    if not os.path.exists(path):
        return set()
    return {l.split()[0] for l in open(path) if l.strip() and not l.startswith('#')}

def meta_fields(meta_dir):
    # every package a meta or task names (Depends, Recommends), from make-meta.py's output
    have = set()
    if not meta_dir:
        return have
    for d in os.listdir(meta_dir):
        c = os.path.join(meta_dir, d, 'DEBIAN', 'control')
        if not os.path.exists(c):
            continue
        for l in open(c):
            if l.startswith(('Depends:', 'Recommends:', 'Pre-Depends:')):
                for alt in l.split(':', 1)[1].split(','):
                    for name in alt.split('|'):
                        name = name.strip().split(' ')[0]
                        if name:
                            have.add(name)
    return have

def placed(meta_dir=None, image=None):
    have = meta_fields(meta_dir)
    if image:
        for l in open(image, errors='replace'):
            if l.startswith('ii'):
                have.add(l.split()[1].split(':')[0])
    base = os.path.join(HERE, '..', 'data', 'sparkylinux-2026.09-x86_64-kde.txt')
    for l in open(base, errors='replace'):   # the KDE edition's names, the image's base (iso-build/base-list.sh)
        if l.startswith('ii'):
            have.add(l.split()[1].split(':')[0])
    for l in open(os.path.join(HERE, 'not-on-image.tsv')):   # left out on purpose, each with its reason
        if l.strip() and not l.startswith('#'):
            have.add(l.split('\t')[0])
    for n in LISTS:
        have |= read_list(n)
    for l in open(os.path.join(HERE, 'roles.tsv')):
        if l.strip() and not l.startswith('#'):
            have.add(l.split('\t')[0])
    tsv = os.path.join(HERE, 'integrations.tsv')
    for l in open(tsv):
        if l.strip() and not l.startswith('#'):
            have |= set(l.rstrip('\n').split('\t')[:2])
    return have

def programs(paths):
    found = {}
    for path in paths:
        opener = gzip.open if path.endswith('.gz') else lzma.open if path.endswith('.xz') else open
        with opener(path, 'rt', errors='replace') as f:
            for line in f:
                parts = line.rstrip('\n').rsplit(None, 1)
                if len(parts) != 2:
                    continue
                file, owners = parts
                if file.startswith('usr/share/applications/') and file.endswith('.desktop'):
                    for o in owners.split(','):
                        found.setdefault(o.rsplit('/', 1)[-1], file)
    return found

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__ or 'usage: check-programs-placed.py <Contents-amd64> [...]')
    args = sys.argv[1:]
    metas = image = None
    while args[:1] in (['--metas'], ['--image']):
        if args[0] == '--metas':
            metas = args[1]
        else:
            image = args[1]
        args = args[2:]
    progs = programs(args)
    have = placed(metas, image)
    loose = sorted(p for p in progs if p not in have)
    print(f'{len(progs)} programs in the repository, {len(progs) - len(loose)} placed')
    for p in loose:
        print(f'not in any list: {p} ({progs[p]})')
    sys.exit(1 if loose else 0)

if __name__ == '__main__':
    main()
