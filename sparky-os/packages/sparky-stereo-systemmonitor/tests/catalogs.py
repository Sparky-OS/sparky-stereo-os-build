#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
# The ten catalogues of the pages' words and of the problem: the same keys, the same number of %s per key, no empty
# sentence, not English where English is not the language, except the words KDE itself leaves as in English
# (CPU, GPU, the list separator, Swap, Applications) (the edition's required languages: en pl pt_BR fr de es ja ko zh_CN
# zh_TW).
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REQUIRED = ["en", "pl", "pt_BR", "fr", "de", "es", "ja", "ko", "zh_CN", "zh_TW"]
SAME_AS_ENGLISH = {("lang", "LOCAL5"), ("lang", "LOCAL7"), ("lang", "LOCAL13"), ("lang", "LOCAL17"), ("lang", "LOCAL20")}


def load(folder, lang):
    out = {}
    for line in open(os.path.join(HERE, "..", folder, lang), encoding="utf-8"):
        m = re.fullmatch(r'(LOCAL[0-9]+)="([^"]*)"\n?', line)
        if m:
            out[m.group(1)] = m.group(2)
        elif line.strip() and not line.startswith("#"):
            raise SystemExit("%s/%s: a line that is no message: %r" % (folder, lang, line))
    return out


failed = []
for folder in ("lang", "problems-lang"):
    present = sorted(os.listdir(os.path.join(HERE, "..", folder)))
    if present != sorted(REQUIRED):
        failed.append("%s: languages %s" % (folder, present))
    en = load(folder, "en")
    for lang in REQUIRED:
        msgs = load(folder, lang)
        if set(msgs) != set(en):
            failed.append("%s/%s: keys %s" % (folder, lang, sorted(set(msgs) ^ set(en))))
        for key, text in msgs.items():
            if not text.strip() and key != "LOCAL13":
                failed.append("%s/%s %s: empty" % (folder, lang, key))
            if text.count("%s") != en.get(key, "").count("%s"):
                failed.append("%s/%s %s: %d %%s, English has %d" % (folder, lang, key, text.count("%s"),
                                                                    en[key].count("%s")))
            if lang != "en" and text == en.get(key) and (folder, key) not in SAME_AS_ENGLISH:
                failed.append("%s/%s %s: the English text" % (folder, lang, key))
for line in failed:
    print("FAIL", line)
print("catalogues: %d failures" % len(failed))
sys.exit(1 if failed else 0)
