#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
# Every sentence the code shows is in the table (strings.py), with its context: the QML's i18ndc("sparky-stereo-throw",
# CONTEXT, TEXT) and the C++'s ki18nc / i18nc (CONTEXT, TEXT), literal strings only (adjacent literals joined). A call
# whose text is not a literal (the device table's generation words) is the table's own business and is skipped here.
# Usage: check-sources.py [RECIPE_DIR]; exit status = the number of sentences missing from the table.
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RECIPE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..")
spec = importlib.util.spec_from_file_location("strings", os.path.join(HERE, "strings.py"))
strings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(strings)
table = {(c, m) for c, m, _ in strings.DAEMON + strings.PAGE}

LIT = r'"(?:[^"\\]|\\.)*"'
LITS = rf'((?:{LIT}\s*)+)'
QML = re.compile(rf'i18ndc\(\s*"sparky-stereo-throw"\s*,\s*{LITS},\s*{LITS}[,)]')
CPP = re.compile(rf'\bk?i18nc\(\s*{LITS},\s*{LITS}[,)]')


def joined(text):
    parts = re.findall(LIT, text)
    return "".join(bytes(p[1:-1], "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") for p in parts)


# the daemon's kept failures: fail(CONTEXT, MESSAGE, ...) and Tell::failure(ID, CONTEXT, MESSAGE, ...), the context a
# QStringLiteral starting with "@" or a constant set to one
QSL = rf'QStringLiteral\(\s*({LIT})\s*\)'
KEPT = re.compile(rf'(?:{QSL}|\b([A-Z]\w*))\s*,\s*{QSL}')
CONST = re.compile(rf'\b([A-Z]\w*)\s*(?:=|\()\s*{QSL}')

found = []
for name in sorted(os.listdir(os.path.join(RECIPE, "src"))):
    if not name.endswith((".cpp", ".h")):
        continue
    source = open(os.path.join(RECIPE, "src", name), encoding="utf-8").read()
    consts = {m.group(1): joined(m.group(2)) for m in CONST.finditer(source)}
    for m in KEPT.finditer(source):
        context = joined(m.group(1)) if m.group(1) else consts.get(m.group(2), "")
        if context.startswith("@"):
            found.append((f"src/{name}", context, joined(m.group(3))))
for folder, pattern, exts in (("kcm/ui", QML, (".qml",)), ("src", CPP, (".cpp", ".h")), ("kcm", CPP, (".cpp",))):
    base = os.path.join(RECIPE, folder)
    for name in sorted(os.listdir(base)):
        if not name.endswith(exts):
            continue
        source = open(os.path.join(base, name), encoding="utf-8").read()
        for m in pattern.finditer(source):
            found.append((f"{folder}/{name}", joined(m.group(1)), joined(m.group(2))))

missing = [(where, c, m) for where, c, m in found if (c, m) not in table]
for where, c, m in missing:
    print(f"FAIL {where}: not in the table: [{c}] {m}")
print(f"{len(found)} sentences in the sources, {len(missing)} missing from the table")
sys.exit(len(missing))
