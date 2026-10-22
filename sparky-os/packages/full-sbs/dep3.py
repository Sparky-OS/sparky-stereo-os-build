#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
"""Export fork commits as DEP-3 Debian patches.

Usage: dep3.py REPO REV NUMBER PREFIX DEST [ORIGIN_URL]
REV is one commit; the patch is DEST/<NUMBER><PREFIX>-<slug>.patch. ORIGIN_URL is the fork's web
address (commit URL = ORIGIN_URL/commit/<sha>).
"""
import re
import subprocess
import sys
from pathlib import Path

repo, rev, number, prefix, dest = sys.argv[1:6]
origin = sys.argv[6] if len(sys.argv) > 6 else None
raw = subprocess.check_output(['git', '-C', repo, 'format-patch', '--stdout', '-1', '--no-signature', rev], text=True)
sha = re.match(r'From ([0-9a-f]{40}) ', raw).group(1)
head, rest = raw.split('\n', 1)
header, body = rest.split('\n\n', 1)
subject = re.search(r'^Subject: (?:\[PATCH[^\]]*\] )?(.*?)(?=\n[A-Z][A-Za-z-]*: |\Z)', header, re.M | re.S).group(1)
subject = re.sub(r'\n ', ' ', subject).strip()
date = re.search(r'^Date: (.*)$', header, re.M).group(1)
author = re.search(r'^From: (.*)$', header, re.M).group(1)
message, diff = body.split('\n---\n', 1)
trailers = re.findall(r'^Assisted-by:.*$', message, re.M)
text = re.sub(r'^Assisted-by:.*$', '', message, flags=re.M).strip()
lines = (subject + ('\n\n' + text if text else '')).split('\n')
description = '\n'.join(' ' + l if l.strip() else ' .' for l in lines).lstrip()
update = subprocess.check_output(['date', '-d', date, '+%Y-%m-%d'], text=True).strip()
slug = re.sub(r'[^A-Za-z0-9]+', '-', subject).strip('-')
if len(slug) > 56:
    slug = slug[:56].rsplit('-', 1)[0]
out = Path(dest) / f'{number}{prefix}-{slug}.patch'
out.parent.mkdir(parents=True, exist_ok=True)
fields = f'Description: {description}\nAuthor: {author}\n'
if origin:
    fields += f'Origin: {origin}/' + ('-/' if 'gitlab' in origin or 'invent' in origin else '') + f'commit/{sha}\n'
fields += f'Forwarded: no\nLast-Update: {update}\n' + ''.join(t + '\n' for t in trailers)
out.write_text(fields + '---\n' + diff)
print(out)
