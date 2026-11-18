#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Drops from each vendored crate's .cargo-checksum.json the files that are not on disk and that no build reads.

`cargo vendor` lists every file of a crate, Cargo.toml.orig (the manifest as the author wrote it, before cargo normalised it)
included, and cargo refuses a crate whose listed file is missing. dpkg-source leaves such `.orig` files out of a source tree it
unpacks. Only an entry whose file is absent and whose name ends in `.orig` is dropped; every other missing or changed file stops
the build, as cargo has it. Usage: strip-missing-checksums.py VENDORDIR
"""
import json
import os
import sys

vendor = sys.argv[1]
dropped = 0
for crate in sorted(os.listdir(vendor)):
	path = os.path.join(vendor, crate, '.cargo-checksum.json')
	with open(path) as f:
		data = json.load(f)
	files = data.get('files', {})
	gone = [n for n in files if n.endswith('.orig') and not os.path.exists(os.path.join(vendor, crate, n))]
	for n in gone:
		del files[n]
	if gone:
		with open(path, 'w') as f:
			json.dump(data, f, separators=(',', ':'))
		dropped += len(gone)
print(f'strip-missing-checksums: {dropped} absent .orig entries dropped from {vendor}')
