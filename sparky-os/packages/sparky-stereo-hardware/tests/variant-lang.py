#!/usr/bin/python3
# The notice of the mismatch guard (ORDER 108) in the ten languages: LOCAL84 (the title) and LOCAL85 (the text, two %s: the packages, the
# processor's level) exist in every problems-lang file, with the same placeholders and the command the Repair runs.
import pathlib, re
here = pathlib.Path(__file__).resolve().parent.parent / 'problems-lang'
langs = 'en de es fr pl pt_BR ja ko zh_CN zh_TW'.split()
for l in langs:
    t = (here / l).read_text(encoding='utf-8')
    m = {k: v for k, v in re.findall(r'^(LOCAL8[45])="((?:[^"\\]|\\.)*)"$', t, re.M)}
    assert set(m) == {'LOCAL84', 'LOCAL85'}, (l, sorted(m))
    assert m['LOCAL85'].count('%s') == 2 and 'sparky-stereo-hardware --variants' in m['LOCAL85'], (l, m['LOCAL85'])
    assert m['LOCAL84'].strip() and '%' not in m['LOCAL84'], l
    print('PASS problems-lang/%s has LOCAL84 and LOCAL85 (two %%s, the Repair command)' % l)
