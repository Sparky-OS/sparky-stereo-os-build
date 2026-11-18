#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
"""The licence table of a Go vendor tree: one row per module of vendor/modules.txt, read from the module's own files.

Usage: vendor-licences.py vendor/modules.txt GOMODCACHE TEXTSDIR  >  vendor-licences.tsv
TEXTSDIR receives a copy of every legal file named in the table (TEXTSDIR/MODULE/PATH), which debian/copyright quotes.

go mod vendor copies only the packages a build needs, with the legal files beside them; a module's other folders stay in the
module cache, which holds the whole module as published, so the licence files are read there (go-release-packaging.md).
A row is `module<TAB>version<TAB>licence<TAB>files<TAB>note`; files are `path:sha256` joined by `;`, root files and, one level
down, a bundled project's own licence files (go-hid bundles hidapi). What a module's files do not state is `not-stated`,
never guessed. The licence name is decided by the text's own title or standard sentences.
"""
import hashlib
import os
import re
import sys

LEGAL = re.compile(r'^(licen[cs]e|copying|copyright|patents|notice|unlicense)([-._].*)?$', re.I)


def escaped(path):
	return re.sub(r'[A-Z]', lambda m: '!' + m.group(0).lower(), path)


def classify(text):
	t = ' '.join(text.split()).lower()
	if 'your choice of exactly one of the following two licenses' in t:
		return 'FTL-or-GPL-2.0-or-later (the user chooses)'
	if 'gnu general public license' in t[:400] and 'version 3' in t[:600]:
		return 'GPL-3.0-only-text'
	if 'gnu general public license' in t[:400] and 'version 2' in t[:600]:
		return 'GPL-2.0-text'
	if 'gnu lesser general public license' in t[:400]:
		return 'LGPL-text'
	if 'apache license' in t[:200] and 'version 2.0' in t[:300]:
		return 'Apache-2.0'
	if 'mozilla public license' in t[:200]:
		return 'MPL-2.0'
	if 'freetype project license' in t[:400]:
		return 'FTL'
	if 'your choice of exactly one of the following two licenses' in t:
		return 'FTL-or-GPL-2.0-or-later (the user chooses)'
	if 'permission is hereby granted, free of charge' in t:
		return 'MIT'
	if 'redistribution and use in source and binary forms' in t:
		clauses = 'neither the name' in t or 'the names of its contributors' in t or 'endorse or promote' in t
		return 'BSD-3-Clause' if clauses else 'BSD-2-Clause'
	if 'additional ip rights grant' in t:
		return 'Google-patent-grant'
	return 'not-stated'


def legal_files(root):
	found = []
	for base, dirs, files in os.walk(root):
		depth = base[len(root):].count(os.sep)
		if depth > 2:
			dirs[:] = []
			continue
		dirs[:] = sorted(d for d in dirs if not d.startswith('.') and d not in ('vendor', 'testdata'))
		in_licenses = os.path.basename(base).lower() in ('licenses', 'licences')
		for name in sorted(files):
			if in_licenses or LEGAL.match(name.rsplit('.', 1)[0] if name.endswith(('.txt', '.md')) else name):
				found.append(os.path.relpath(os.path.join(base, name), root))
	return found


def main(modules_txt, cache, texts):
	rows = []
	for line in open(modules_txt):
		m = re.match(r'^# (\S+) (\S+)$', line)
		if not m:
			continue
		module, version = m.groups()
		root = os.path.join(cache, escaped(module) + '@' + version)
		if not os.path.isdir(root):
			sys.exit(f'{module}@{version}: not in the module cache {cache}')
		names = legal_files(root)
		digests, kinds, note = [], [], ''
		for rel in names:
			data = open(os.path.join(root, rel), 'rb').read()
			dest = os.path.join(texts, module, rel)
			os.makedirs(os.path.dirname(dest), exist_ok=True)
			open(dest, 'wb').write(data)
			digests.append(f'{rel}:{hashlib.sha256(data).hexdigest()}')
			kinds.append((rel, classify(data.decode('utf-8', 'replace'))))
		top = [k for rel, k in kinds if os.sep not in rel and k not in ('Google-patent-grant', 'not-stated')]
		if any(k.startswith('FTL-or-GPL') for k in top):
			top = [k for k in top if k.startswith('FTL-or-GPL')]
		licence = '+'.join(sorted(set(top))) if top else 'not-stated'
		bundled = sorted({k for rel, k in kinds if os.sep in rel and k not in ('Google-patent-grant', 'not-stated')} - set(top))
		if bundled:
			note = 'bundled projects: ' + ', '.join(f'{rel} ({k})' for rel, k in kinds if os.sep in rel and k in bundled)
		if not digests:
			note = 'no licence file at the module root'
		# C sources a module bundles (go-hid carries hidapi) state their own licence in their headers
		stated = set()
		for name in sorted(os.listdir(root)):
			if name.endswith(('.c', '.h')):
				for text in open(os.path.join(root, name), errors='replace').read().split('\n')[:60]:
					if re.search(r'licen[cs]ed|license|GPL|BSD', text, re.I) and not text.startswith('//go:'):
						stated.add(text.strip(' */#').strip())
		if stated:
			note = (note + '; ' if note else '') + 'C file headers say: ' + ' | '.join(sorted(stated)[:6])
		rows.append((module, version, licence, ';'.join(digests), note))
	print('# module\tversion\tlicence\tfiles (path:sha256)\tnote')
	for row in sorted(rows):
		print('\t'.join(row))


main(sys.argv[1], sys.argv[2], sys.argv[3])
