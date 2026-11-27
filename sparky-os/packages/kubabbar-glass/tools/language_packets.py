#!/usr/bin/env python3
"""Every translated text of Kubabbar Glass 9 (row 147, milestones 1 to 3), from the recipe, for a reading by a second
lab's model: OUT/strings.json (one row per distinct text: its ids, sources and the ten languages) and three packets,
OUT/packet-A.txt (pl, pt_BR, fr), packet-B.txt (de, es) and packet-C.txt (ja, ko, zh_CN, zh_TW), each the reading's
instructions and every English source beside its translation. GPL-3.0-only.
Usage: language_packets.py RECIPE_DIR OUT_DIR"""
import configparser
import json
import re
import sys
from pathlib import Path

LANGS = ["en", "pl", "pt_BR", "fr", "de", "es", "ja", "ko", "zh_CN", "zh_TW"]
recipe = Path(sys.argv[1])
outdir = Path(sys.argv[2])
outdir.mkdir(parents=True, exist_ok=True)
out = outdir / "strings.json"
items = {}  # id -> {"source": ..., lang: text}


def add(ident, source, lang, text):
    entry = items.setdefault(ident, {"source": source})
    entry[lang] = text


# 1. strings9.py: every dict of the ten languages
sys.path.insert(0, str(recipe / "tools"))
import strings9  # noqa: E402
for name, value in vars(strings9).items():
    if isinstance(value, dict) and "en" in value:
        for lang in LANGS:
            add("strings9." + name, "tools/strings9.py", lang, value[lang])

# 2. the helpers' message catalogues (LOCALn="...")
for catalogue in ("glass9", "scrolling9"):
    for lang in LANGS:
        for line in (recipe / "lang" / catalogue / lang).read_text(encoding="utf-8").splitlines():
            m = re.match(r'^(LOCAL\d+)="(.*)"$', line)
            if m:
                add(f"lang/{catalogue}.{m.group(1)}", f"lang/{catalogue}", lang, m.group(2))


# 3. desktop-style files: Name, Comment, Description with [lang]
def desktop_fields(path, prefix):
    parser = configparser.RawConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    parser.read(path, encoding="utf-8")
    for section in parser.sections():
        for key, text in parser.items(section):
            m = re.match(r"^(Name|Comment|Description)(?:\[([A-Za-z_]+)\])?$", key)
            if m:
                lang = m.group(2) or "en"
                if lang in LANGS:
                    add(f"{prefix}.{m.group(1)}", str(path.relative_to(recipe)), lang, text)


for path in sorted((recipe / "share/color-schemes").glob("kubabbar-glass-9*.colors")):
    desktop_fields(path, "colors." + path.stem)
desktop_fields(recipe / "etc/xdg/autostart/kubabbar-glass-9-sync.desktop", "autostart.kubabbar-glass-9-sync")
for path in [recipe / "share/sddm/themes/kubabbar-glass-9/metadata.desktop",
             recipe / "share/aurorae/themes/kubabbar-glass-9/metadata.desktop"]:
    desktop_fields(path, "meta." + path.parent.parent.name + "." + path.parent.name)

# 4. KPackage metadata.json: KPlugin Name and Description with [lang]
for path in sorted(recipe.glob("share/**/kubabbar-glass-9*/metadata.json")):
    plugin = json.loads(path.read_text(encoding="utf-8")).get("KPlugin", {})
    for key, text in plugin.items():
        m = re.match(r"^(Name|Description)(?:\[([A-Za-z_]+)\])?$", key)
        if m and isinstance(text, str):
            lang = m.group(2) or "en"
            if lang in LANGS:
                rel = path.relative_to(recipe)
                add(f"meta.{rel.parts[-3]}.{rel.parts[-2]}.{m.group(1)}", str(rel), lang, text)

# one row per distinct text: identical rows (generated copies of strings9) collapse, their ids kept
rows = {}
for ident, entry in sorted(items.items()):
    key = json.dumps({lang: entry.get(lang) for lang in LANGS}, ensure_ascii=False, sort_keys=True)
    rows.setdefault(key, {"ids": [], "sources": set(), **{lang: entry.get(lang) for lang in LANGS}})
    rows[key]["ids"].append(ident)
    rows[key]["sources"].add(entry["source"])
table = []
for row in rows.values():
    row["sources"] = sorted(row["sources"])
    missing = [lang for lang in LANGS if not row.get(lang)]
    row["missing"] = missing
    table.append(row)
out.write_text(json.dumps(table, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(len(items), "ids,", len(table), "distinct texts;",
      sum(1 for r in table if r["missing"]), "with a missing language:",
      [(r["ids"][0], r["missing"]) for r in table if r["missing"]])

NAMES = {"pl": "Polish", "pt_BR": "Brazilian Portuguese", "fr": "French", "de": "German", "es": "Spanish",
         "ja": "Japanese", "ko": "Korean", "zh_CN": "Simplified Chinese (zh_CN)", "zh_TW": "Traditional Chinese (zh_TW)"}
GROUPS = {"A": ["pl", "pt_BR", "fr"], "B": ["de", "es"], "C": ["ja", "ko", "zh_CN", "zh_TW"]}
INTRO = """You are reviewing the user-interface translations of a desktop look for KDE Plasma 6 (a theme family named "Kubabbar Glass 9": colour schemes, a Plasma style, a window decoration, a wallpaper, a login screen for SDDM, a menu bar layout, and two small command-line helpers whose messages appear in the desktop's notifications).
Read every translation below against its English source and report only real findings:
- a wrong or changed meaning, something left out or added;
- a term that is not the one KDE's own translation team for that language uses on the Plasma desktop (scroll bar, scroll arrows, tooltip, pop-up, panel, dock, task manager, application menu, window list, colour scheme, global theme or look, login screen, notification);
- grammar, spelling, register (polite form where the language expects it) and the language's own punctuation and typography (quotation marks, spaces before punctuation in French, full-width punctuation in Chinese and Japanese);
- the same English term translated in two different ways across the strings of one language;
- a %s placeholder missing, added or out of order (each %s is filled in the order given, so the translation must keep the English order of the %s).
Names stay as they are and are not findings: Kubabbar Glass, Kubabbar Glass 9, Kvantum, Sparky 9 "Tiamat", Sparky Stereo OS 9 "Mashtabba", Daniel Ramos, kubabbar-glass-9-sync. The colour scheme names Ivy, Rose, Gold, Teal and Graphite are translated as plain colour or plant words.
Answer with one table per language, columns: id | problem | the whole corrected text. When a language has no finding, write "LANGUAGE: no finding". Do not rewrite a string that is correct, and do not report style preferences that are not errors.
"""
for group, langs in GROUPS.items():
    parts = [INTRO, "Languages in this packet: " + ", ".join(NAMES[lang] for lang in langs) + ".", ""]
    for lang in langs:
        parts.append(f"=== {NAMES[lang]} ({lang}) ===")
        for r in table:
            parts.append(f"[{r['ids'][0]}]\n  EN: {r['en']}\n  {lang}: {r[lang]}")
        parts.append("")
    (outdir / f"packet-{group}.txt").write_text("\n".join(parts), encoding="utf-8")
