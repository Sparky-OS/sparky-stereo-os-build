#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
# fill-ts.py TRANSLATIONS.json: writes each language's strings into translations/calamares-sparky_<code>.ts,
# in the order of calamares-sparky_en.ts (the source), and makes the file of a language that has none yet
# from the English one. A language's list must have exactly one string per source string.
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TR = os.path.join(HERE, 'translations')


def main():
    data = json.load(open(sys.argv[1], encoding='utf-8'))
    en_path = os.path.join(TR, 'calamares-sparky_en.ts')
    sources = [m.find('source').text for m in ET.parse(en_path).iter('message')]
    for code, strings in data.items():
        if code.startswith('_'):
            continue
        if len(strings) != len(sources):
            raise SystemExit('%s: %d strings for %d sources' % (code, len(strings), len(sources)))
        path = os.path.join(TR, 'calamares-sparky_%s.ts' % code)
        base = path if os.path.exists(path) else en_path
        if [m.find('source').text for m in ET.parse(base).iter('message')] != sources:
            raise SystemExit('%s: its sources differ from calamares-sparky_en.ts' % base)
        # line by line, so the file keeps the layout lupdate gave it
        out, i = [], 0
        for line in open(base, encoding='utf-8').read().split('\n'):
            if line.lstrip().startswith('<TS '):
                line = re.sub(r' language="[^"]*"', ' language="%s"' % code, line)
            elif line.lstrip().startswith('<translation'):
                indent = line[:len(line) - len(line.lstrip())]
                line = '%s<translation>%s</translation>' % (indent, escape(strings[i]))
                i += 1
            out.append(line)
        if i != len(sources):
            raise SystemExit('%s: %d translation lines for %d sources' % (base, i, len(sources)))
        with open(path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(out))
        print('%s: %d strings' % (os.path.basename(path), len(strings)))


main()
