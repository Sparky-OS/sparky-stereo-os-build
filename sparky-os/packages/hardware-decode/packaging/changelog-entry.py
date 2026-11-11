#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
"""changelog-entry.py CHANGELOG VERSION ITEM...: puts a new entry for unstable on top of a Debian changelog, in the
form repo/lc-successor.py writes its own (whole words, 79 columns, Daniel's packaging identity)."""
from pathlib import Path
import sys
import textwrap

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'repo'))
import reproducible

path, version, items = sys.argv[1], sys.argv[2], sys.argv[3:]
if not items:
    sys.exit(__doc__)
body = '\n'.join(textwrap.fill(i, width=79, initial_indent='  * ', subsequent_indent='    ', break_on_hyphens=False,
                               break_long_words=False) for i in items)
with open(path, encoding='utf-8') as f:
    text = f.read()
name = text.split(' ', 1)[0]
head = f'{name} ({version}) unstable; urgency=medium\n\n{body}\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '
with open(path, 'w', encoding='utf-8') as f:
    f.write(head + reproducible.rfc2822(reproducible.recipe_epoch([Path(__file__).resolve().parents[1]])) + '\n\n' + text)
