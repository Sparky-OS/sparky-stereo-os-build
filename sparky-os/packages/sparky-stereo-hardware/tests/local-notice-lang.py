#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# The notices of a LACT or a HeadsetControl made by upstream's makefile beside the package (ORDER 108 milestone 11) in the ten languages: LOCAL90 and
# LOCAL92 (the titles) and LOCAL91 and LOCAL93 (the texts, no placeholder) exist in every problems-lang file, say it in that language (not the
# English text) and carry the commands of the way over unchanged.
import pathlib, re
here = pathlib.Path(__file__).resolve().parent.parent / 'problems-lang'
langs = 'en de es fr pl pt_BR ja ko zh_CN zh_TW'.split()
steps = {
    'LOCAL91': ['sudo systemctl disable --now lactd', 'sudo rm /usr/local/bin/lact /usr/local/lib/systemd/system/lactd.service', 'sudo systemctl daemon-reload',
                'sudo systemctl enable --now lactd', '/etc/lact/config.yaml', '/usr/share/doc/lact/README.Debian'],
    'LOCAL93': ['sudo rm /usr/local/bin/headsetcontrol /usr/local/lib/udev/rules.d/70-headsets.rules', 'sudo udevadm control --reload-rules'],
}
english = {}
for l in langs:
    t = (here / l).read_text(encoding='utf-8')
    m = {k: v for k, v in re.findall(r'^(LOCAL9[0-3])="((?:[^"\\]|\\.)*)"$', t, re.M)}
    assert set(m) == {'LOCAL90', 'LOCAL91', 'LOCAL92', 'LOCAL93'}, (l, sorted(m))
    assert '%' not in ''.join(m.values()), l
    for key, items in steps.items():
        for step in items:
            assert step in m[key], (l, key, step)
    if l == 'en':
        english = m
    else:
        assert all(m[k] != english[k] for k in m), l
    print('PASS problems-lang/%s has LOCAL90 to LOCAL93 with the steps' % l)
