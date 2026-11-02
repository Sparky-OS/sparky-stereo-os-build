#!/usr/bin/env python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Check embedded package diagnostics and reject absent authoring catalogues in Docker."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

PACKAGE = Path(__file__).resolve().parents[1] / 'sparky-stereo-grub-l10n'
LANGUAGES = ('en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW')


def messages(language):
    return {int(k): v for k, v in re.findall(r'^LOCAL(\d+)="(.*)"$',
                                            (PACKAGE / 'lang' / language).read_text(), re.M)}


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    control = root / 'control'
    subprocess.run(['dpkg-deb', '-e', sys.argv[1], str(control)], check=True)
    english = messages('en')
    for name in ('postinst', 'postrm'):
        source = (control / name).read_text()
        boundary = '\ncase "$1" in' if name == 'postinst' else '\nif [ "$1" = "remove" ]'
        assert boundary in source
        definitions = source.split(boundary, 1)[0]
        for language in LANGUAGES:
            for action in ('configure', 'remove', 'purge'):
                key = 21 if action == 'configure' else 56
                probe = root / 'probe'
                probe.write_text(definitions + '\nlog=/var/log/sparky-stereo-grub-l10n.log\n'
                                 + 'failure ' + action + ' 7\n')
                run = subprocess.run(['sh', str(probe)], capture_output=True, text=True,
                                     env=dict(os.environ, LANG=language + '.UTF-8'))
                assert run.returncode == 0, run.stderr
                assert messages(language)[key] % ('update-grub', '7') in run.stderr, (name, language, action)
                assert english[key] % ('update-grub', '7') in run.stderr, (name, language, action)
                assert messages(language)[1] % '/var/log/sparky-stereo-grub-l10n.log' in run.stderr
            print(name, language, 'configure/remove/purge diagnostics: PASS')
    for language in LANGUAGES:
        copy = root / language
        shutil.copytree(PACKAGE / 'lang', copy)
        (copy / language).unlink()
        run = subprocess.run(['python3', str(PACKAGE / 'tools/maintainer-messages.py'), str(copy)],
                             capture_output=True, text=True)
        assert run.returncode != 0 and not run.stdout and str(copy / language) in run.stderr
        print('missing', language, 'stops embedding: PASS')
print('54 embedded diagnostic cases and 9 missing-catalogue cases passed')
