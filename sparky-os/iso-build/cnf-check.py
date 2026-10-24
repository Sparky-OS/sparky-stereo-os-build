#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/24
# Reads command-not-found's database (/var/lib/command-not-found/commands.db) and checks that it names a package for a Debian-only
# command, a deb-multimedia-only command (the first command whose package only deb-multimedia's Contents list, found in the package
# lists beside the database) and an edition-only command. Usage: cnf-check.py DEBIAN-COMMAND EDITION-COMMAND
import glob, sqlite3, subprocess, sys

DB = '/var/lib/command-not-found/commands.db'


def packages(path):
    out = subprocess.run(['/usr/lib/apt/apt-helper', 'cat-file', path], capture_output=True, text=True, check=True).stdout
    found = {}
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[0].startswith(('usr/bin/', 'usr/sbin/', 'bin/', 'sbin/')):
            for owner in parts[1].split(','):
                found.setdefault(owner.rsplit('/', 1)[-1].strip(), parts[0].rsplit('/', 1)[-1])
    return found


def main():
    debian_cmd, edition_cmd = sys.argv[1:3]
    c = sqlite3.connect(DB)

    def who(cmd):
        return [r[0] for r in c.execute('select p.name from commands m join packages p using(pkgID) where m.command=?', (cmd,))]

    deb = {}
    for f in glob.glob('/var/lib/apt/lists/*debian.org_debian_dists_testing_*Contents-*'):
        deb.update(packages(f))
    dmo = {}
    for f in glob.glob('/var/lib/apt/lists/*deb-multimedia.org_dists_*Contents-*'):
        dmo.update(packages(f))
    only = sorted((p, cmd) for p, cmd in dmo.items() if p not in deb)
    bad = 0
    for label, cmd in (('Debian only', debian_cmd), ('edition only', edition_cmd)) + ((('deb-multimedia only', only[0][1]),) if only else ()):
        r = who(cmd)
        print('%s: %s -> %s' % (label, cmd, r))
        bad += 0 if r else 1
    if not only:
        print('deb-multimedia only: no command found in its Contents lists')
        bad += 1
    sys.exit(1 if bad else 0)


main()
