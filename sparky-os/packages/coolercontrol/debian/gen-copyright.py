#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Write debian/copyright of coolercontrol from HEAD.txt and the licence tables. Usage: gen-copyright.py HEAD.txt TABLE.tsv:PREFIX:DOCDIR ... > copyright
(PREFIX: where the table's packages sit in the source tree, e.g. coolercontrold/vendor or coolercontrol-ui/node_modules; DOCDIR: where their legal files are installed)

Packages are grouped by the licence expression their Cargo.toml states, one stanza for each expression. The expression is
written in Debian's syntax (a Cargo `/` is `OR`; `or`/`and` are lower case). A licence this script does not know stops it.
Reads files only.
"""
import csv
import re
import sys

NAMES = {'MIT': 'Expat', 'Apache-2.0': 'Apache-2.0', 'Unicode-3.0': 'Unicode-3.0', 'Unlicense': 'Unlicense', 'ISC': 'ISC',
         'BSD-3-Clause': 'BSD-3-Clause', 'BSD-2-Clause': 'BSD-2-Clause', 'Zlib': 'Zlib', '0BSD': '0BSD', 'MPL-2.0': 'MPL-2.0',
         'CC0-1.0': 'CC0-1.0', 'BSL-1.0': 'BSL-1.0', 'GPL-2.0-only': 'GPL-2', 'LGPL-2.1-or-later': 'LGPL-2.1+',
         'LGPL-3.0-or-later': 'LGPL-3+', 'CDLA-Permissive-2.0': 'CDLA-Permissive-2.0', 'LLVM-exception': 'LLVM-exception', 'BlueOak-1.0.0': 'BlueOak-1.0.0', 'CC-BY-4.0': 'CC-BY-4.0', 'Python-2.0': 'Python-2.0', 'MIT-0': 'MIT-0', 'GPL-3.0-or-later': 'GPL-3+', 'AGPL-3.0-or-later': 'AGPL-3+', 'Apache-2.0 WITH LLVM-exception': 'Apache-2.0', 'OFL-1.1': 'OFL-1.1', 'NCSA': 'NCSA', 'CC-BY-3.0': 'CC-BY-3.0'}
COMMON = {'GPL-3+': 'GPL-3', 'AGPL-3+': 'AGPL-3', 'CC-BY-4.0': 'CC-BY-4.0', 'Apache-2.0': 'Apache-2.0', 'MPL-2.0': 'MPL-2.0', 'CC0-1.0': 'CC0-1.0', 'GPL-2': 'GPL-2', 'LGPL-2.1+': 'LGPL-2.1',
          'LGPL-3+': 'LGPL-3'}
TEXTS = {
	'Expat': """ Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
 documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
 FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.""",
	'ISC': """ Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted,
 provided that the above copyright notice and this permission notice appear in all copies.
 .
 THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
 CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
 NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.""",
	'BSD-2-Clause': """ Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
 following conditions are met:
 .
 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 .
 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.
 .
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT
 NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.""",
	'Zlib': """ This software is provided 'as-is', without any express or implied warranty. In no event will the authors be held liable
 for any damages arising from the use of this software.
 .
 Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and
 redistribute it freely, subject to the following restrictions:
 .
 1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use
 this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
 .
 2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
 .
 3. This notice may not be removed or altered from any source distribution.""",
}
TEXTS['BSD-3-Clause'] = TEXTS['BSD-2-Clause'].replace(
	' .\n THIS SOFTWARE IS PROVIDED BY',
	' .\n 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived\n from this software without specific prior written permission.\n .\n THIS SOFTWARE IS PROVIDED BY')
SHIPPED = (' The text is the legal file of each package that states this licence, installed under /usr/share/doc/coolercontrold/ '
           '(its SHA-256 is pinned in the debian/*licences.tsv tables).')


def debian(expr):
	e = expr.replace('/', ' OR ')
	e = re.sub(r'\bWITH LLVM-exception\b', 'with-LLVM-exception', e)
	e = e.replace('(', '').replace(')', '')
	atoms = re.split(r'\s+(?:OR|AND)\s+', e)
	out = e
	for atom in sorted(set(atoms), key=len, reverse=True):
		base = atom.strip().replace('with-LLVM-exception', '').strip()
		if base not in NAMES:
			sys.exit(f'licence {base!r} ({expr!r}) has no name in gen-copyright.py: read the crate\'s files and add it')
		out = out.replace(atom.strip(), NAMES[base] + ('-with-LLVM-exception' if 'with-LLVM-exception' in atom else ''))
	return out.replace(' OR ', ' or ').replace(' AND ', ' and ').replace('  ', ' ')


def main(head, specs):
	groups, missing = {}, []
	for spec in specs:
		table, prefix, docdir = spec.split(':')
		for row in csv.reader(open(table, encoding='utf-8'), delimiter='\t'):
			if not row or row[0].startswith('#'):
				continue
			crate, version, licence, files, note = (row + [''])[:5]
			if licence.startswith('FILE:'):
				sys.exit(f'{crate}: a licence file instead of a licence field: read it and add the case')
			if licence in ('NONE', ''):
				licence = 'UNSTATED'
			groups.setdefault(licence, []).append((prefix, docdir, crate))
			if not files:
				missing.append(crate)
	out = [open(head, encoding='utf-8').read().rstrip('\n'), '']
	used = set()
	for licence in sorted(groups):
		if licence == 'UNSTATED':
			name = 'public-domain-or-unstated'
		else:
			name = debian(licence)
		for atom in re.split(r' (?:or|and) ', name):
			used.add(atom)
		out.append('Files: ' + '\n  '.join(f'{p}/{c}/*' for p, d, c in groups[licence]))
		out.append('Copyright: see the legal files of the packages, installed under /usr/share/doc/coolercontrold/')
		out.append('License: ' + name)
		out.append('Comment: licence field of the package: ' + licence)
		out.append('')
	if missing:
		out.insert(1, '# Packages that hold no legal file (the licence is the one their package.json or Cargo.toml states): ' + ' '.join(sorted(set(missing))) + '\n')
	for atom in sorted(used | {'Expat', 'GPL-3+'}):
		if atom == 'GPL-3+':
			out.append('License: GPL-3+')
			out.append(' On Debian systems, the full text of the GNU General Public License version 3 can be found in /usr/share/common-licenses/GPL-3.')
		elif atom == 'public-domain-or-unstated':
			out.append('License: public-domain-or-unstated')
			out.append(' The package states no licence field; its files, if it has any, are in /usr/share/doc/coolercontrold/. It is a build tool or data of the interface build, named in the list above.')
		elif atom.endswith('-with-LLVM-exception'):
			out.append(f'License: {atom}')
			out.append(' Apache-2.0 with the LLVM exception; see Apache-2.0 and the legal file of the packages that state it.')
		elif atom in COMMON:
			out.append(f'License: {atom}')
			out.append(f' On Debian systems, the full text can be found in /usr/share/common-licenses/{COMMON[atom]}.')
		elif atom in TEXTS:
			out.append(f'License: {atom}')
			out.append(TEXTS[atom])
		else:
			out.append(f'License: {atom}')
			out.append(SHIPPED)
		out.append('')
	print('\n'.join(out).rstrip('\n'))


main(sys.argv[1], sys.argv[2:])
