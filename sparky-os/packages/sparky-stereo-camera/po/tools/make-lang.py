#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make lang/LANG (the problems engine's message files, KEY="text" with %s per argument) from translations.py and the page's
own name, so the engine says a refused saved choice in the sentences the page uses.  Usage: make-lang.py LANG_DIR PLUGIN_JSON"""
import json, re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from translations import LANGS, T

out, plugin = Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text())["KPlugin"]
out.mkdir(exist_ok=True)


def sentence(msgid, index, tail=""):
    text = T[msgid][index] if index >= 0 else msgid
    text = re.sub(r"%(\d)", lambda m: "%s", text)  # %1 %2 %3 arrive in order, one %s each
    return text + tail


M = ["%1: the saved size and format were not applied. ", "%1: the saved value of %2 was not applied. ", "%1: the camera no longer lists the control %2."]
for index, lang in enumerate(["en"] + LANGS):
    i = index - 1
    title = plugin["Name"] if lang == "en" else plugin.get("Name[%s]" % lang)
    l2 = sentence(M[0], i) + "%s"
    l3 = sentence(M[1], i) + "%s"
    l4 = sentence(M[2], i)
    (out / lang).write_text('LOCAL1="%s"\nLOCAL2="%s"\nLOCAL3="%s"\nLOCAL4="%s"\n' % (title, l2.replace('"', '\\"'), l3.replace('"', '\\"'), l4.replace('"', '\\"')), encoding="utf-8")
print("ok", len(LANGS) + 1, "files")
