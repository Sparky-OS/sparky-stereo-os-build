#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""The licence table of a cargo vendor tree: one row per crate of vendor/, read from the crate's own files.

Usage: crate-licences.py VENDOR TEXTSDIR  >  crate-licences.tsv
A row is `crate<TAB>version<TAB>licence<TAB>files<TAB>note`: the licence is the crate's `license` field of Cargo.toml
(or `FILE:` and its `license-file`), the files are `path:sha256` of every legal file at the crate's root, joined by `;`.
Authors and e-mail addresses are never written: the table is committed. The legal files themselves are copied to
TEXTSDIR/CRATE/ (they carry their authors' addresses and stay out of git: build.sh takes them from the vendor tree and
stops unless each has the hash the committed table pins). A crate with no legal file says so in its note.
"""
import hashlib
import os
import re
import shutil
import sys
import tomllib

LEGAL = re.compile(r'^(licen[cs]e|copying|unlicense|notice|copyright|patents)([-._].*)?$', re.I)


def main(vendor, texts):
	rows = []
	for crate in sorted(os.listdir(vendor)):
		root = os.path.join(vendor, crate)
		with open(os.path.join(root, 'Cargo.toml'), 'rb') as f:
			package = tomllib.load(f)['package']
		licence = package.get('license') or ('FILE:' + package.get('license-file', ''))
		names = sorted(n for n in os.listdir(root) if os.path.isfile(os.path.join(root, n)) and LEGAL.match(n))
		if package.get('license-file') and package['license-file'] not in names and os.path.isfile(os.path.join(root, package['license-file'])):
			names.append(package['license-file'])
		digests = []
		for name in names:
			data = open(os.path.join(root, name), 'rb').read()
			digests.append(f'{name}:{hashlib.sha256(data).hexdigest()}')
			dest = os.path.join(texts, crate, name)
			os.makedirs(os.path.dirname(dest), exist_ok=True)
			open(dest, 'wb').write(data)
		rows.append((crate, package['version'], licence, ';'.join(digests), '' if digests else 'no legal file in the crate'))
	print('# crate\tversion\tlicence (Cargo.toml)\tfiles (path:sha256)\tnote')
	for row in rows:
		print('\t'.join(row))


main(sys.argv[1], sys.argv[2])
