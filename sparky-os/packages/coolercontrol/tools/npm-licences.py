#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""The licence table of a vendored npm tree: one row per package directory of node_modules (nested ones included), read from the package's own files.

Usage: npm-licences.py NODE_MODULES TEXTSDIR  >  npm-licences.tsv
A row is `package<TAB>version<TAB>licence<TAB>files<TAB>note`: the licence is the `license` field of package.json (or the `licenses` list), the files are
`path:sha256` of every legal file at the package's root, joined by `;`. Authors and e-mail addresses are never written: the table is committed. The legal
files are copied to TEXTSDIR/PACKAGE@VERSION/ (they carry their authors' addresses and stay out of git: build.sh takes them from the tree and stops unless each
has the hash the committed table pins). A package with no legal file says so in its note.
"""
import hashlib, json, os, re, shutil, sys

LEGAL = re.compile(r'^(licen[cs]e|copying|unlicense|notice|copyright|patents)([-._].*)?$', re.I)


def packages(root):
	for base, dirs, files in os.walk(root, followlinks=False):
		if 'package.json' in files and os.path.basename(os.path.dirname(base)) in ('node_modules',) or ('package.json' in files and os.path.basename(os.path.dirname(base)).startswith('@') and os.path.basename(os.path.dirname(os.path.dirname(base))) == 'node_modules'):
			yield base
		dirs[:] = [d for d in dirs if d not in ('.bin', '.cache')]


def main(root, texts):
	rows = []
	for pkg in sorted(packages(root)):
		try:
			meta = json.load(open(os.path.join(pkg, 'package.json'), encoding='utf-8'))
		except (ValueError, OSError):
			continue
		name, version = meta.get('name', os.path.basename(pkg)), meta.get('version', '')
		lic = meta.get('license')
		if isinstance(lic, dict):
			lic = lic.get('type')
		if not lic and isinstance(meta.get('licenses'), list):
			lic = ' OR '.join(x.get('type', '') if isinstance(x, dict) else str(x) for x in meta['licenses'])
		names = sorted(n for n in os.listdir(pkg) if os.path.isfile(os.path.join(pkg, n)) and LEGAL.match(n))
		digests = []
		rel = os.path.relpath(pkg, root)
		for n in names:
			data = open(os.path.join(pkg, n), 'rb').read()
			digests.append(f'{n}:{hashlib.sha256(data).hexdigest()}')
			dest = os.path.join(texts, rel, n)
			os.makedirs(os.path.dirname(dest), exist_ok=True)
			open(dest, 'wb').write(data)
		note = '' if digests else 'no legal file in the package'
		if not lic:
			note = (note + '; ' if note else '') + 'no licence field'
		rows.append((rel, version, lic or 'NONE', ';'.join(digests), note))
	print('#path\tversion\tlicence\tfiles\tnote')
	for r in rows:
		print('\t'.join(r))


if __name__ == '__main__':
	main(sys.argv[1], sys.argv[2])
