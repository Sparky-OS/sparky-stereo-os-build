#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Append the Sound Quality page strings to the already patched 6.7.4 catalogues."""
import difflib
import json
from pathlib import Path
import re
import sys

source, output=map(Path,sys.argv[1:])
strings=json.loads((Path(__file__).parent/'sound-format-strings.json').read_text())
required={'en','pl','pt_BR','fr','de','es','ja','ko','zh_CN','zh_TW'}
assert set(strings)==required
patch=[]
for lang,translations in strings.items():
    assert len(translations)==len(strings['en'])
    if lang=='en': continue
    relative=f'po/{lang}/kcm_pulseaudio.po'
    old=(source/relative).read_text()
    new=old.rstrip('\n')+'\n'
    for message, translated in zip(strings['en'],translations):
        assert sorted(re.findall(r'%[0-9]+',message))==sorted(re.findall(r'%[0-9]+',translated))
        key='msgid '+json.dumps(message,ensure_ascii=False)
        # Reuse an upstream context-free translation when one already exists.
        if any(key in entry.splitlines() and not any(line.startswith('msgctxt ') for line in entry.splitlines())
               for entry in old.split('\n\n')):
            continue
        new+='\n#. Sound Quality: formats, rates and the graph settings.\n'
        new+=key+'\nmsgstr '+json.dumps(translated,ensure_ascii=False)+'\n'
    patch.append(f'diff --git a/{relative} b/{relative}\n')
    patch.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+relative,tofile='b/'+relative))
output.write_text(''.join(patch))
