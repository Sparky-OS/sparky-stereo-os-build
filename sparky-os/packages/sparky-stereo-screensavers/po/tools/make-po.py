#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""Make po/kcm_sparkystereo_screensavers.pot and po/LANG/kcm_sparkystereo_screensavers.po from the page's sources and translations.py.

Usage: make-po.py PACKAGE_DIR [--check]   (--check: write nothing, fail when a sentence of the sources has no entry,
an entry is used by no source, a placeholder differs or a committed file is not what would be written)"""
import re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from translations import LANGS, PLURAL_FORMS, T

DOMAIN = 'kcm_sparkystereo_screensavers'
root = Path(sys.argv[1])
check = '--check' in sys.argv
STRING = r'"((?:[^"\\]|\\.)*)"'
found = []   # (context or None, msgid, plural or None)
for path in sorted(list((root/'src').rglob('*.qml')) + list((root/'src').rglob('*.cpp'))):
    text = path.read_text(encoding='utf-8')
    for match in re.finditer(r'\bi18n(c|p|cp)?\(\s*' + STRING + r'(?:\s*,\s*' + STRING + r')?(?:\s*,\s*' + STRING + r')?', text):
        kind, a, b, c = match.group(1) or '', match.group(2), match.group(3), match.group(4)
        un = lambda s: s.replace('\\"', '"').replace('\\\\', '\\') if s is not None else None
        a, b, c = un(a), un(b), un(c)
        entry = {'': (None, a, None), 'c': (a, b, None), 'p': (None, a, b), 'cp': (a, b, c)}[kind]
        if entry not in found:
            found.append(entry)

def key(entry):
    context, msgid, plural = entry
    if plural is not None:
        return (msgid, plural)
    return (context + '|' + msgid) if context else msgid

def quote(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def catalogue(lang):
    index = LANGS.index(lang) if lang in LANGS else None
    out = ['# Sparky Stereo OS, the Screensavers page of System Settings.', '# SPDX-License-Identifier: GPL-2.0-or-later', 'msgid ""', 'msgstr ""',
           '"Project-Id-Version: sparky-stereo-screensavers\\n"', '"Language: %s\\n"' % (lang or ''), '"MIME-Version: 1.0\\n"',
           '"Content-Type: text/plain; charset=UTF-8\\n"', '"Content-Transfer-Encoding: 8bit\\n"',
           '"Plural-Forms: %s\\n"' % PLURAL_FORMS.get(lang or 'en', PLURAL_FORMS['en']), '']
    for entry in found:
        context, msgid, plural = entry
        if context:
            out.append('msgctxt ' + quote(context))
        out.append('msgid ' + quote(msgid))
        if plural is not None:
            out.append('msgid_plural ' + quote(plural))
            forms = T[key(entry)][index] if index is not None else ([msgid, plural] if lang == 'en' else ['', ''])
            out += ['msgstr[%d] %s' % (n, quote(form)) for n, form in enumerate(forms)]
        else:
            out.append('msgstr ' + quote(T[key(entry)][index] if index is not None else (msgid if lang == 'en' else '')))
        out.append('')
    return '\n'.join(out)

problems = []
keys = [key(entry) for entry in found]
problems += ['no translation entry for %r' % (k,) for k in keys if k not in T]
problems += ['entry used by no source: %r' % (k,) for k in T if k not in keys]
places = lambda s: sorted(re.findall(r'%\d', s))
for k, value in T.items():
    if len(value) != len(LANGS):
        problems.append('%r has %d languages' % (k, len(value)))
        continue
    english = k[0] if isinstance(k, tuple) else k.split('|', 1)[-1]
    for lang, text in zip(LANGS, value):
        for form in (text if isinstance(text, list) else [text]):
            if not form or places(form) != places(english):
                problems.append('%s: placeholders differ in %r' % (lang, form))
        if isinstance(text, list) and len(text) != int(PLURAL_FORMS[lang].split('nplurals=')[1][0]):
            problems.append('%s: %d plural forms for %r' % (lang, len(text), k))
if problems:
    sys.exit('\n'.join(problems))
files = {root/'po'/(DOMAIN + '.pot'): catalogue(None), root/'po'/'en'/(DOMAIN + '.po'): catalogue('en')}
files.update({root/'po'/lang/(DOMAIN + '.po'): catalogue(lang) for lang in LANGS})
for path, text in files.items():
    if check:
        if not path.is_file() or path.read_text(encoding='utf-8') != text:
            problems.append('%s is not what the sources and translations.py give' % path)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
if problems:
    sys.exit('\n'.join(problems))
print('%d sentences, %d languages' % (len(found), len(LANGS) + 1))
