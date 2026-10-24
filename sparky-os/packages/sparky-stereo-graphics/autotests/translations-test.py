#!/usr/bin/python3 -I
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Every required language has every message translated, none fuzzy, and each translation keeps the
# placeholders of its source (%1, %2) and the plural forms its language needs.
import re
import subprocess
import sys
from pathlib import Path

po_dir = Path(sys.argv[1])
languages = ["pl", "pt_BR", "fr", "de", "ja", "ko", "zh_CN", "zh_TW"]
nplurals = {"pl": 3, "pt_BR": 2, "fr": 2, "de": 2, "ja": 1, "ko": 1, "zh_CN": 1, "zh_TW": 1}


def q(text):
    text = text.strip()
    return text[1:-1] if text.startswith('"') and text.endswith('"') else text


def parse(path):
    entries, cur, key = [], None, None
    for line in path.read_text(encoding="utf8").split("\n"):
        if line.startswith("#,") and "fuzzy" in line:
            cur = cur or {}
            cur["fuzzy"] = True
        if line.startswith("msgctxt "):
            cur = cur or {}
            cur["ctxt"], key = q(line[8:]), "ctxt"
        elif line.startswith("msgid_plural "):
            cur["plural"], key = q(line[13:]), "plural"
        elif line.startswith("msgid "):
            cur = cur or {}
            cur["id"], key = q(line[6:]), "id"
        elif line.startswith("msgstr["):
            cur.setdefault("strs", []).append(q(line.split(" ", 1)[1]))
            key = "strs"
        elif line.startswith("msgstr "):
            cur["strs"], key = [q(line[7:])], "strs"
        elif line.startswith('"') and cur is not None:
            if key == "strs":
                cur["strs"][-1] += q(line)
            elif key:
                cur[key] += q(line)
        elif not line.strip():
            if cur and cur.get("id"):
                entries.append(cur)
            cur, key = None, None
    if cur and cur.get("id"):
        entries.append(cur)
    return entries


pot = parse(po_dir / "kcm_sparkystereo_graphics.pot")
failed = 0
for lang in languages:
    path = po_dir / lang / "kcm_sparkystereo_graphics.po"
    if not path.exists():
        print("FAIL missing", path)
        failed += 1
        continue
    check = subprocess.run(["msgfmt", "--check", "--statistics", "-o", "/dev/null", str(path)], capture_output=True, text=True)
    if check.returncode != 0 or "untranslated" in check.stderr or "fuzzy" in check.stderr:
        print("FAIL msgfmt", lang, check.stderr)
        failed += 1
    entries = parse(path)
    if len(entries) != len(pot):
        print("FAIL", lang, "has", len(entries), "messages, the template", len(pot))
        failed += 1
        continue
    for src, tr in zip(pot, entries):
        if src["id"] != tr["id"] or src.get("ctxt") != tr.get("ctxt"):
            print("FAIL", lang, "message order or text differs at", src["id"])
            failed += 1
            continue
        if tr.get("fuzzy"):
            print("FAIL", lang, "fuzzy", src["id"])
            failed += 1
        want = sorted(re.findall(r"%\d", src["id"] + src.get("plural", "")))
        if "plural" in src:
            if len(tr["strs"]) != nplurals[lang]:
                print("FAIL", lang, "plural forms", len(tr["strs"]), "for", src["id"])
                failed += 1
            for form in tr["strs"]:
                if form == '':
                    print("FAIL", lang, "empty plural form for", src["id"])
                    failed += 1
        else:
            if tr["strs"][0] == '':
                print("FAIL", lang, "untranslated", src["id"])
                failed += 1
        for form in tr["strs"]:
            got = sorted(set(re.findall(r"%\d", form)))
            need = sorted(set(want))
            # a language may drop the number of a plural when the message has none to show, but never %2
            if not set(got) <= set(need) or (("%2" in need) and "%2" not in got) or ("%1" in need and "%1" not in got and "plural" not in src and nplurals[lang] > 1 and False):
                print("FAIL", lang, "placeholders", got, "vs", need, "in", src["id"])
                failed += 1
import json
meta = json.loads((po_dir.parent / "src" / "kcm_sparkystereo_graphics.json").read_text(encoding="utf8"))
for lang in languages:
    for key in ("Name", "Description"):
        if not meta["KPlugin"].get("%s[%s]" % (key, lang)):
            print("FAIL the page's metadata has no", key, "in", lang)
            failed += 1
    # System Settings finds the page by these words too
    if not meta.get("X-KDE-Keywords[%s]" % lang):
        print("FAIL the page's metadata has no search keywords in", lang)
        failed += 1
print("translations: %d languages checked, %d failures" % (len(languages), failed))
sys.exit(1 if failed else 0)
