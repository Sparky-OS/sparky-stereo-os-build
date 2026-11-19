#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Compile from our PO files and the exact, unmodified Debian source inputs."""
import argparse
import gettext
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
PIN = json.loads((HERE / 'tasksel-source.json').read_text())
LOCAL3 = 'Language support was not changed: the update would also remove %s, which it does not manage. Keep them with apt-mark manual or remove them yourself, then retry the update.'
LOCAL4 = 'Language support could not be completed: %s. The details are in the journal (journalctl -u sparky-stereo-language-tasks). Retry the update when this is fixed.'


def verify(directory):
    directory = Path(directory)
    for name, expected in PIN['files'].items():
        path = directory / name
        if path.stat().st_size != expected['size'] or hashlib.sha256(path.read_bytes()).hexdigest() != expected['sha256']:
            raise ValueError('Debian tasksel input differs from the pinned source: ' + name)
    descriptor = (directory / 'tasksel_3.92.dsc').read_text()
    if not re.search(r'^Source: tasksel$', descriptor, re.M) or not re.search(r'^Version: 3\.92$', descriptor, re.M):
        raise ValueError('Expected Debian source tasksel 3.92')
    checksums = re.search(r'^Checksums-Sha256:\n((?:[ \t].*\n)+)', descriptor, re.M)
    if checksums is None:
        raise ValueError('Debian descriptor has no SHA256 component list')
    records = {name: (digest, int(size)) for digest, size, name in
               (line.split() for line in checksums[1].splitlines())}
    archive = directory / 'tasksel_3.92.tar.xz'
    if records.get(archive.name) != (hashlib.sha256(archive.read_bytes()).hexdigest(), archive.stat().st_size):
        raise ValueError('Debian source archive does not match its descriptor')
    return archive


def compile_catalogues(tree, source_dir):
    archive = verify(source_dir)
    name = 'sparky-stereo-language-tasks'
    with tempfile.TemporaryDirectory(prefix='tasksel-po-', dir=tree.parent) as work, tarfile.open(archive) as upstream:
        work = Path(work)
        for po in sorted((HERE / 'po').glob('*.po')):
            lang = po.stem
            own = tree / 'usr/share/locale' / lang / 'LC_MESSAGES' / (name + '.mo')
            own.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['msgfmt', '--check-format', '-o', str(own), str(po)], check=True)
            merged = tree / 'usr/share' / name / 'tasksel' / lang / 'debian-tasks.mo'
            merged.parent.mkdir(parents=True, exist_ok=True)
            if lang == 'en':
                shutil.copyfile(own, merged)
            else:
                # These are the same Debian PO members used by the original recipe.
                # Read only the named regular member, never extract an untrusted tree.
                member = upstream.getmember('tasksel-3.92/po/' + lang + '.po')
                if not member.isfile():
                    raise ValueError('Expected a regular Debian PO member: ' + member.name)
                original = work / (lang + '.po')
                original.write_bytes(upstream.extractfile(member).read())
                combined = work / 'merged.po'
                subprocess.run(['msgcat', '--use-first', str(po), str(original), '-o', str(combined)], check=True)
                subprocess.run(['msgfmt', '--check-format', '-o', str(merged), str(combined)], check=True)
            translation = gettext.GNUTranslations(own.open('rb'))
            target = tree / 'usr/share/sparky' / name / lang
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('LOCAL1=' + json.dumps(translation.gettext('Shared language support'), ensure_ascii=False) + '\n'
                              'LOCAL2=' + json.dumps(translation.gettext('Language support could not be completed: %s. Check the network and retry the update.'), ensure_ascii=False) + '\n'
                              'LOCAL3=' + json.dumps(translation.gettext(LOCAL3), ensure_ascii=False) + '\n'
                              'LOCAL4=' + json.dumps(translation.gettext(LOCAL4), ensure_ascii=False) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--tree', type=Path)
    args = parser.parse_args()
    if args.tree is None:
        verify(args.source_dir)
    else:
        compile_catalogues(args.tree, args.source_dir)
