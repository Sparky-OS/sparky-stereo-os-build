#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate the catalogues and action metadata from one ten-language table."""
import csv
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
with (ROOT / 'controller/translations.tsv').open() as stream:
    rows = list(csv.DictReader(stream, delimiter='\t'))
LANGUAGES = ['en', 'de', 'es', 'fr', 'pl', 'pt_BR', 'ja', 'ko', 'zh_CN', 'zh_TW']
assert len(rows) == len({row['en'] for row in rows})
texts = {row['en']: row for row in rows}
for row in rows:
    assert list(row) == LANGUAGES and all(row.values()), row
    for lang in LANGUAGES:
        assert sorted(re.findall(r'%\d+', row[lang])) == sorted(re.findall(r'%\d+', row['en'])), row
sources = [p for folder in ['controller', 'src'] for p in (ROOT / folder).rglob('*.cpp') if 'tests' not in p.parts]
messages = set()
for p in sources:
    messages.update(re.findall(r'(?:i18n\(|i18nd\("kcm_ums", )"([^"]+)"', p.read_text()))
messages.update(re.findall(r'i18n\("([^"]+)"', (ROOT / 'src/ui/main.qml').read_text()))
assert messages <= texts.keys(), messages - texts.keys()
for lang in LANGUAGES[1:]:
    header = ('Project-Id-Version: kcm-ums 0.2.0\nPO-Revision-Date: 2026-11-11 00:00+0000\nLast-Translator: Sparky Stereo OS translators\nLanguage-Team: Sparky Stereo OS\nLanguage: ' + lang + '\nMIME-Version: 1.0\n'
              'Content-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\n')
    content = ['# Translation draft for review.\nmsgid ""\nmsgstr ' + json.dumps(header, ensure_ascii=False)]
    for text in sorted(messages):
        content.append('msgid ' + json.dumps(text, ensure_ascii=False) + '\nmsgstr ' + json.dumps(texts[text][lang], ensure_ascii=False))
    folder = ROOT / 'po' / lang
    folder.mkdir(exist_ok=True)
    (folder / 'kcm_ums.po').write_text('\n\n'.join(content) + '\n')
    subprocess.run(['msgfmt', '--check', '-o', '/dev/null', str(folder / 'kcm_ums.po')], check=True)

for kind, text in [('tv', 'Play on TV'), ('headset', 'Play on the headset')]:
    path = ROOT / 'controller/purpose' / (kind + '.json')
    meta = json.loads(path.read_text())
    for lang in LANGUAGES[1:]:
        meta['KPlugin']['Name[' + lang + ']'] = texts[text][lang]
        meta['KPlugin']['Description[' + lang + ']'] = texts[text][lang]
        meta['X-Purpose-ActionDisplay[' + lang + ']'] = texts[text][lang]
    path.write_text(json.dumps(meta, ensure_ascii=False, indent=4) + '\n')

def names(text):
    return '\n'.join('Name' + (('[' + lang + ']') if lang != 'en' else '') + '=' + texts[text][lang] for lang in LANGUAGES)

menus = ROOT / 'controller/ums-play.desktop'
menus.write_text('[Desktop Entry]\nType=Service\nMimeType=video/*;audio/*;image/*;\nActions=TV;Headset;\n'
                 'X-KDE-RequiredNumberOfUrls=1\nX-KDE-Protocols=file\n'
                 'X-KDE-Priority=TopLevel\n\n[Desktop Action TV]\n' + names('Play on TV') +
                 '\nIcon=video-display\nExec=ums-renderer --target tv -- %u\n\n[Desktop Action Headset]\n' + names('Play on the headset') +
                 '\nIcon=view-preview\nExec=ums-renderer --target headset -- %u\n')
(ROOT / 'controller/ums-renderer.desktop').write_text('[Desktop Entry]\nType=Application\n' + names('Media Devices') +
                 '\nIcon=video-display\nExec=ums-renderer\nTerminal=false\nCategories=AudioVideo;Network;\n')
print(f'PASS {len(messages)} runtime messages in {len(LANGUAGES)} languages; two menus and two Purpose plugins')
