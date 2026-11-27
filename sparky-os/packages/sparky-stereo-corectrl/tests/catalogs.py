#!/usr/bin/python3
# The ten catalogues: the same keys, the same number of %s per key, no empty sentence, not English where English is not
# the language (the edition's required languages: en pl pt_BR fr de es ja ko zh_CN zh_TW).
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LANG = os.path.join(HERE, "..", "problems-lang")
REQUIRED = ["en", "pl", "pt_BR", "fr", "de", "es", "ja", "ko", "zh_CN", "zh_TW"]


def load(lang):
    out = {}
    for line in open(os.path.join(LANG, lang), encoding="utf-8"):
        m = re.fullmatch(r'(LOCAL[0-9]+)="([^"]*)"\n?', line)
        if m:
            out[m.group(1)] = m.group(2)
        elif line.strip():
            raise SystemExit("%s: a line that is no message: %r" % (lang, line))
    return out


failed = []
present = sorted(os.listdir(LANG))
if present != sorted(REQUIRED):
    failed.append("languages: %s" % present)
en = load("en")
for lang in REQUIRED:
    msgs = load(lang)
    if set(msgs) != set(en):
        failed.append("%s: keys %s" % (lang, sorted(set(msgs) ^ set(en))))
    for key, text in msgs.items():
        if not text.strip():
            failed.append("%s %s: empty" % (lang, key))
        if text.count("%s") != en.get(key, "").count("%s"):
            failed.append("%s %s: %d %%s, English has %d" % (lang, key, text.count("%s"), en[key].count("%s")))
        if lang != "en" and text == en.get(key):
            failed.append("%s %s: the English text" % (lang, key))
for line in failed:
    print("FAIL  " + line)
print("%d languages, %d keys, %d failures" % (len(REQUIRED), len(en), len(failed)))
sys.exit(1 if failed else 0)
