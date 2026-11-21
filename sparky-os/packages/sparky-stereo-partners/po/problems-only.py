#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
"""problems-only.py PODIR OUTDIR: copies of the page's catalogues holding only what the problems engine shows for this package:
the sentences the command keeps (keep(NAME, CONTEXT, TEXT, ...)), the action's label and the notification's title. The journal
catalogue is made from these, so a page sentence still waiting for the translations lane (po/pending-translation.txt) never
stops the build, and a kept problem's sentence missing from a language still does."""
import re
import subprocess
import sys
from pathlib import Path

podir, outdir = Path(sys.argv[1]), Path(sys.argv[2])
source = (Path(__file__).resolve().parents[1] / 'bin' / 'sparky-stereo-partners').read_text(encoding='utf-8')
keys = {('@title notification', 'A partner cannot work'), ('@action:button', 'Open Partners')}
for m in re.finditer(r"""keep\([^,]+,\s*'(@[^']*)',\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')""", source):
    keys.add((m.group(1), (m.group(2) if m.group(2) is not None else m.group(3)).replace("\\'", "'")))
def unquote(line, word):
    return line[len(word) + 2:-1].replace('\\"', '"').replace('\\\\', '\\')


count = 0
for path in [podir / 'kcm_sparkystereo_partners.pot', *sorted(podir.glob('*/kcm_sparkystereo_partners.po'))]:
    target = outdir / path.relative_to(podir)
    target.parent.mkdir(parents=True, exist_ok=True)
    text = subprocess.run(['msgcat', '--no-wrap', str(path)], capture_output=True, text=True, check=True).stdout
    kept, found = [], set()
    for block in text.split('\n\n'):
        lines = block.strip('\n').splitlines()
        context = next((unquote(l, 'msgctxt') for l in lines if l.startswith('msgctxt "')), None)
        msgid = next((unquote(l, 'msgid') for l in lines if l.startswith('msgid "')), None)
        if (msgid == '' and context is None and not kept) or (context, msgid) in keys:
            kept.append('\n'.join(lines))
            found.add((context, msgid))
    missing = keys - found
    if missing:
        raise SystemExit('problems-only.py: %s lacks %s' % (path, sorted(missing)))
    target.write_text('\n\n'.join(kept) + '\n', encoding='utf-8')
    count = len(kept) - 1
print('problems-only.py: %d sentences of kept problems in each catalogue' % count)
