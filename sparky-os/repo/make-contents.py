#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/24
# Writes Contents-<arch> files, which apt-file and command-not-found read (Debian's archive format: one line per path,
# "path<tab>section/package[,section/package]", sorted by path, no directories). A package of Architecture: all is listed in
# every architecture's file and in Contents-all, as Debian's archive does. The output is deterministic.
# Usage: make-contents.py OUTDIR "ARCH ARCH..." DEB...
import os, subprocess, sys, tarfile

def main():
    out, arches = sys.argv[1], sys.argv[2].split()
    files = {a: {} for a in arches}
    for path in sys.argv[3:]:
        f = subprocess.run(['dpkg-deb', '-f', path, 'Package', 'Architecture', 'Section'], capture_output=True, text=True, check=True).stdout
        field = {k: v.strip() for k, _, v in (l.partition(':') for l in f.splitlines() if not l.startswith(' '))}
        pkg, arch = field['Package'], field['Architecture']
        owner = (field.get('Section') or 'misc').split('/')[-1].lower() + '/' + pkg
        proc = subprocess.Popen(['dpkg-deb', '--fsys-tarfile', path], stdout=subprocess.PIPE)
        names = []
        with tarfile.open(fileobj=proc.stdout, mode='r|') as tf:
            for m in tf:
                if m.isdir():
                    continue
                n = m.name[2:] if m.name.startswith('./') else m.name
                if n and n != '.':
                    names.append(n)
        if proc.wait() != 0:
            sys.exit('cannot list ' + path)
        for a in (arches if arch == 'all' else [arch]):
            if a in files:
                for n in names:
                    files[a].setdefault(n, set()).add(owner)
    os.makedirs(out, exist_ok=True)
    for a in arches:
        with open(os.path.join(out, 'Contents-' + a), 'w') as o:
            for n in sorted(files[a]):
                o.write('%s\t%s\n' % (n, ','.join(sorted(files[a][n]))))

main()
