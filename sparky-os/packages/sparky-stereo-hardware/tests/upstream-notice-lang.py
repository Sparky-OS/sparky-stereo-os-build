#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# The notice of upstream's own OpenLinkHub install beside the package (ORDER 108 milestone 8) in the ten languages: LOCAL88 (the title) and
# LOCAL89 (the text, no placeholder) exist in every problems-lang file, say it in that language (not the English line), and carry the
# commands of the way over and the README.Debian that holds them, unchanged.
import pathlib, re
here = pathlib.Path(__file__).resolve().parent.parent / 'problems-lang'
langs = 'en de es fr pl pt_BR ja ko zh_CN zh_TW'.split()
english = None
steps = ['systemctl disable --now OpenLinkHub', 'cp -a /opt/OpenLinkHub/database /opt/OpenLinkHub/config.json /var/lib/openlinkhub/',
         'chown -R openlinkhub:openlinkhub /var/lib/openlinkhub', 'rm /etc/systemd/system/OpenLinkHub.service /etc/udev/rules.d/99-openlinkhub.rules',
         'systemctl enable --now OpenLinkHub', '/usr/share/doc/openlinkhub/README.Debian']
for l in langs:
    t = (here / l).read_text(encoding='utf-8')
    m = {k: v for k, v in re.findall(r'^(LOCAL8[89])="((?:[^"\\]|\\.)*)"$', t, re.M)}
    assert set(m) == {'LOCAL88', 'LOCAL89'}, (l, sorted(m))
    assert m['LOCAL88'].strip() and '%' not in m['LOCAL88'] + m['LOCAL89'], l
    for step in steps:
        assert step in m['LOCAL89'], (l, step)
    if l == 'en':
        english = m['LOCAL89']
    else:
        assert m['LOCAL89'] != english and m['LOCAL88'] != 'OpenLinkHub from its own installer', l
    print('PASS problems-lang/%s has LOCAL88 and LOCAL89 with the six steps' % l)
