#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make po/LANG/sparky-pjeoffice.po from po/sparky-pjeoffice.pot and qt_strings.py, and the translated data files:
the menu entry, the tray's autostart entry, the Dolphin service menu, the notification file, and the settings page's plugin file.
Every message of the template must have a translation in every language, or this stops. Usage: make-i18n.py PACKAGE_DIR"""
import json, re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from qt_strings import FILES, LANGS, T

root = Path(sys.argv[1])
pot = root / 'po/sparky-pjeoffice.pot'


def pot_ids(path):
    ids, current, collecting = [], '', False
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith('msgid '):
            current, collecting = line[6:].strip()[1:-1], True
        elif line.startswith('msgstr'):
            collecting = False
            if current:
                ids.append(current.replace('\\"', '"').replace('\\n', '\n'))
        elif collecting and line.startswith('"'):
            current += line.strip()[1:-1]
    return ids


def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


ids = pot_ids(pot)
missing = [i for i in ids if i not in T]
extra = [k for k in T if k not in ids]
if missing:
    sys.exit('no translation for: ' + repr(missing))
if extra:
    sys.exit('translated but not in the template: ' + repr(extra))
for index, lang in enumerate(LANGS):
    folder = root / 'po' / lang
    folder.mkdir(exist_ok=True)
    out = ['# PJeOffice Pro on Sparky Stereo OS, %s.\n# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)\n# SPDX-License-Identifier: GPL-3.0-or-later\n' % lang,
           'msgid ""\nmsgstr ""\n"Project-Id-Version: sparky-pjeoffice 0.1.0\\n"\n"Language: %s\\n"\n"MIME-Version: 1.0\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n' % lang]
    for i in ids:
        out.append('msgid "%s"\nmsgstr "%s"\n' % (esc(i), esc(T[i][index])))
    # the tray's catalogue and the settings page's: QML reads its strings from the catalogue named like the plugin
    for domain in ('sparky-pjeoffice', 'kcm_sparkystereo_pjeoffice'):
        (folder / (domain + '.po')).write_text('\n'.join(out), encoding='utf-8')




def keyed(name, key):
    en, tr = FILES[key]
    return ['%s=%s' % (name, en)] + ['%s[%s]=%s' % (name, lang, text) for lang, text in zip(LANGS, tr)]


data = root / 'data'
data.mkdir(exist_ok=True)
(data / 'sparky-pjeoffice.desktop').write_text('\n'.join(
    ['[Desktop Entry]', 'Type=Application', 'Version=1.0', 'Name=PJeOffice Pro'] + keyed('Comment', 'Comment') +
    ['Exec=/usr/bin/sparky-pjeoffice launch --tell', 'Icon=application-certificate', 'Terminal=false', 'Categories=Office;Utility;',
     'Keywords=PJe;PJeOffice;CNJ;assinador;signer;certificate;tribunal;court;', 'StartupNotify=false', 'X-KDE-StartupNotify=false']) + '\n', encoding='utf-8')
(data / 'sparky-pjeoffice-tray.desktop').write_text('\n'.join(
    ['[Desktop Entry]', 'Type=Application', 'Version=1.0', 'Name=PJeOffice Pro tray entry'] +
    [x for x in keyed('Name', 'TrayName')[1:]] +
    ['Exec=/usr/bin/sparky-pjeoffice-tray', 'Icon=application-certificate', 'Terminal=false', 'OnlyShowIn=KDE;',
     'X-KDE-autostart-condition=sparkystereopjeofficerc:General:Autostart:true', 'X-KDE-autostart-phase=2', 'X-KDE-StartupNotify=false']) + '\n', encoding='utf-8')
(data / 'sparky-pjeoffice-sign.desktop').write_text('\n'.join(
    ['[Desktop Entry]', 'Type=Service', 'MimeType=application/pdf;', 'Actions=signWithPJeOffice;', 'X-KDE-Priority=TopLevel',
     '', '[Desktop Action signWithPJeOffice]'] + keyed('Name', 'SignAction') + ['Icon=application-certificate', 'Exec=/usr/bin/sparky-pjeoffice sign-pdf %F']) + '\n', encoding='utf-8')
notify = ['[Global]', 'IconName=application-certificate', 'Name=PJeOffice Pro', 'Comment=PJeOffice Pro', 'DesktopEntry=sparky-pjeoffice', '']
for event, key in (('signerStopped', 'SignerStopped'), ('updateChecked', 'UpdateChecked')):
    notify += ['[Event/%s]' % event] + keyed('Name', key) + ['Action=Popup', '']
(data / 'sparky-pjeoffice.notifyrc').write_text('\n'.join(notify), encoding='utf-8')
plugin = root / 'src/kcm_sparkystereo_pjeoffice.json'
meta = json.loads(plugin.read_text(encoding='utf-8'))
kp = meta['KPlugin']
en, tr = FILES['SettingsDescription']
kp['Description'] = en
for lang, text in zip(LANGS, tr):
    kp['Description[%s]' % lang] = text
plugin.write_text(json.dumps(meta, indent=4, ensure_ascii=False) + '\n', encoding='utf-8')
print('ok', len(ids), 'messages,', len(LANGS), 'languages')
