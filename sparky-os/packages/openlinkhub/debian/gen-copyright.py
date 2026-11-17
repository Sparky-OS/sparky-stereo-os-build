#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
"""Write debian/copyright of openlinkhub from the licence table (vendor-licences.tsv) and the head file.

Usage: gen-copyright.py HEAD.txt TABLE.tsv > copyright
Reads files only. A stanza per vendored module, its licence named as the module's own files say (never guessed), the full
text of each licence kind that is not in /usr/share/common-licenses once, and the edition's own stanza last.
"""
import csv
import sys

SHORT = {'BSD-2-Clause': 'BSD-2-Clause', 'BSD-3-Clause': 'BSD-3-Clause', 'FTL-or-GPL-2.0-or-later (the user chooses)': 'GPL-2+'}
BSD2 = """ Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following
 conditions are met:
 .
 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 .
 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer
 in the documentation and/or other materials provided with the distribution.
 .
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT
 NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."""
BSD3 = BSD2.replace(""" in the documentation and/or other materials provided with the distribution.
""", """ in the documentation and/or other materials provided with the distribution.
 .
 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived
 from this software without specific prior written permission.
""")


def main(head, table):
	out = [open(head, encoding='utf-8').read().rstrip('\n'), '']
	used = set()
	for row in csv.reader(open(table, encoding='utf-8'), delimiter='\t'):
		if not row or row[0].startswith('#'):
			continue
		module, version, licence, files, note = (row + [''])[:5]
		if licence not in SHORT:
			sys.exit(f'{module}: licence {licence!r} has no stanza in gen-copyright.py: read the module\'s files and add it')
		short = SHORT[licence]
		used.add(short)
		names = ' '.join(f.split(':')[0] for f in files.split(';'))
		out.append(f'Files: vendor/{module}/*')
		out.append(f'Copyright: see the legal files of {module} {version} in /usr/share/doc/openlinkhub/vendor-licences/{module}/ ({names})')
		out.append(f'License: {short}')
		if note:
			out.append('Comment: ' + note.replace('\n', ' '))
		out.append('')
	out.append('Files: debian/*')
	out.append('Copyright: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>')
	out.append('License: GPL-3')
	out.append(' Sparky Stereo OS, Daniel Ramos\'s (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Pawel "pavroo" Pijanowski).')
	out.append('')
	out.append('License: GPL-3')
	out.append(' On Debian systems, the full text of the GNU General Public License version 3 can be found in /usr/share/common-licenses/GPL-3.')
	if 'GPL-2+' in used:
		out.append('')
		out.append('License: GPL-2+')
		out.append(' On Debian systems, the full text of the GNU General Public License version 2 can be found in /usr/share/common-licenses/GPL-2.')
	if 'BSD-2-Clause' in used:
		out.append('')
		out.append('License: BSD-2-Clause')
		out.append(BSD2)
	if 'BSD-3-Clause' in used:
		out.append('')
		out.append('License: BSD-3-Clause')
		out.append(BSD3)
	print('\n'.join(out))


main(sys.argv[1], sys.argv[2])
