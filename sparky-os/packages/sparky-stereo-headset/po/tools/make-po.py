#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write po/LANG/kcm_sparkystereo_headset.po (the page, the command and the notifications) and the same catalogue as
plasma_applet_org.sparky.stereo.headset.po (the panel entry reads its own domain), for the ten languages, and the template, from translations.py.
Usage: make-po.py PO_DIR"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from translations import LANGS, T

DOMAINS = ["kcm_sparkystereo_headset", "plasma_applet_org.sparky.stereo.headset"]
po_dir = Path(sys.argv[1])


def quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def head(lang, domain):
    return (f"# Headset page of Sparky Stereo OS, {lang}.\n# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)\n# SPDX-License-Identifier: GPL-3.0-or-later\n"
            f'msgid ""\nmsgstr ""\n"Project-Id-Version: sparky-stereo-headset 0.1.0\\n"\n"Language: {lang}\\n"\n"MIME-Version: 1.0\\n"\n'
            '"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n'
            f'"Plural-Forms: nplurals={1 if lang in ("ja", "ko", "zh_CN", "zh_TW") else 2}; plural={"0" if lang in ("ja", "ko", "zh_CN", "zh_TW") else "(n != 1)"};\\n"\n\n')


for domain in DOMAINS:
    (po_dir / f"{domain}.pot").write_text(head("", domain).replace('"Language: \\n"\n', '') + "".join(f"msgid {quote(e[0])}\nmsgstr \"\"\n\n" for e in T), encoding="utf-8")
    for lang in ["en"] + LANGS:
        out = head(lang, domain)
        for entry in T:
            text = entry[0] if lang == "en" else entry[1 + LANGS.index(lang)]
            out += f"msgid {quote(entry[0])}\nmsgstr {quote(text)}\n\n"
        d = po_dir / lang
        d.mkdir(exist_ok=True)
        (d / f"{domain}.po").write_text(out, encoding="utf-8")
print(len(T), "sentences,", len(LANGS) + 1, "languages,", len(DOMAINS), "catalogues each")
