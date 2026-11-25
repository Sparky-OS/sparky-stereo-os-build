#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""Writes po/sparky-stereo-throw.pot and po/LANG/sparky-stereo-throw.po from strings.py."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import strings  # noqa: E402

PO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOMAIN = "sparky-stereo-throw"


def quote(text):
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + text + '"'


def entries():
    for group in ("DAEMON", "PAGE"):
        yield from getattr(strings, group, [])


def write(path, lang):
    head = ['msgid ""', 'msgstr ""', '"Project-Id-Version: sparky-stereo-throw\\n"', '"MIME-Version: 1.0\\n"',
            '"Content-Type: text/plain; charset=UTF-8\\n"', '"Content-Transfer-Encoding: 8bit\\n"']
    if lang:
        head.append(f'"Language: {lang}\\n"')
        head.append('"Plural-Forms: nplurals=1; plural=0;\\n"' if lang in ("ja", "ko", "zh_CN", "zh_TW")
                    else '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"')
    out = ["\n".join(head), ""]
    seen = set()
    for ctx, msgid, tr in entries():
        if (ctx, msgid) in seen:
            continue
        seen.add((ctx, msgid))
        out.append(f"msgctxt {quote(ctx)}\nmsgid {quote(msgid)}\nmsgstr {quote(tr.get(lang, '') if lang else '')}\n")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))


# the daemon and the command translate in their own domain; the page's QML in the KCM's plugin id (KCMUtils' context),
# so the same table is written under both names
for domain in (DOMAIN, "kcm_sparkystereo_throw"):
    write(os.path.join(PO, domain + ".pot"), None)
    for lang in strings.LANGS:
        write(os.path.join(PO, lang, domain + ".po"), lang)
print("wrote", len(strings.LANGS), "catalogues and the template")
