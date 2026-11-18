#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# The notice of a CoolerControl made by upstream's makefile beside the package (ORDER 108 milestone 14) in the ten languages: LOCAL1 (the title) and LOCAL2 (the text,
# two %s: the files of the copy) exist in every debian/problems-lang file, say it in that language (not the English text) and carry the commands of the way over unchanged.
import pathlib, re
here = pathlib.Path(__file__).resolve().parent.parent / 'debian' / 'problems-lang'
langs = 'en de es fr pl pt_BR ja ko zh_CN zh_TW'.split()
steps = ['sudo systemctl disable --now coolercontrold', 'sudo rm %s', 'sudo systemctl daemon-reload', 'sudo systemctl enable --now coolercontrold',
         '/etc/coolercontrol', '/usr/share/doc/coolercontrold/README.Debian']
english = {}
for l in langs:
    t = (here / l).read_text(encoding='utf-8')
    m = dict(re.findall(r'^(LOCAL\d+)="((?:[^"\\]|\\.)*)"$', t, re.M))
    assert set(m) == {'LOCAL1', 'LOCAL2'}, (l, sorted(m))
    assert m['LOCAL1'].count('%') == 0 and m['LOCAL2'].count('%s') == 2 and m['LOCAL2'].count('%') == 2, l
    for step in steps:
        assert step in m['LOCAL2'], (l, step)
    assert 'lact' not in (m['LOCAL1'] + m['LOCAL2']).replace('LACT', '').lower().replace('coolercontrol', ''), l
    if l == 'en':
        english = m
    else:
        assert all(m[k] != english[k] for k in m), l
    print('PASS debian/problems-lang/%s has LOCAL1 and LOCAL2 with the steps and two %%s' % l)
