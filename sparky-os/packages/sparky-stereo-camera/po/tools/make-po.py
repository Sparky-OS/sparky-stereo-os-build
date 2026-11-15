#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make po/LANG/kcm_sparkystereo_camera.po for the ten languages from the template (po/kcm_sparkystereo_camera.pot),
translations.py (the page's sentences) and the stereo layer's catalogues (the packings' names: a camera and a file read alike).
Usage: make-po.py PO_DIR LAYER_PO_DIR   (LAYER_PO_DIR holds de/stereo-layer_qt.po ...)"""
import re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from translations import LANGS, T

po_dir, layer_dir = Path(sys.argv[1]), Path(sys.argv[2])


def read_po(path):
    """msgid -> msgstr for one catalogue (single-line and multi-line strings; context ignored)."""
    out, cur, mode = {}, {"id": "", "str": ""}, None
    def flush():
        if cur["id"]:
            out[cur["id"]] = cur["str"]
    for line in path.read_text(encoding="utf-8").splitlines() + [""]:
        if line.startswith("msgid "):
            flush(); cur["id"], cur["str"], mode = "", "", "id"
            line = line[6:]
        elif line.startswith("msgstr "):
            mode = "str"; line = line[7:]
        elif line.startswith("msgctxt") or line.startswith("#") or not line.strip():
            if not line.strip() and mode == "str":
                flush(); cur["id"], cur["str"], mode = "", "", None
            continue
        if mode and line.startswith('"'):
            cur["id" if mode == "id" else "str"] += bytes(line.strip()[1:-1], "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if False else line.strip()[1:-1].replace('\\"', '"').replace("\\n", "\n")
    return out


def msgids(pot):
    ids, cur, collecting = [], "", False
    for line in pot.read_text(encoding="utf-8").splitlines():
        if line.startswith("msgid "):
            cur, collecting = line[6:].strip()[1:-1], True
        elif line.startswith("msgstr"):
            collecting = False
            ids.append(cur)
        elif collecting and line.startswith('"'):
            cur += line.strip()[1:-1]
    return [i.replace('\\"', '"').replace("\\n", "\n") for i in ids if i]


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


ids = msgids(po_dir / "kcm_sparkystereo_camera.pot")
header = lambda lang: ('# Camera page of Sparky Stereo OS, %s.\n# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)\n# SPDX-License-Identifier: GPL-3.0-or-later\n'
                       'msgid ""\nmsgstr ""\n"Project-Id-Version: sparky-stereo-camera 0.1.0\\n"\n"Language: %s\\n"\n"MIME-Version: 1.0\\n"\n'
                       '"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n\n') % (lang, lang)
missing = []
for index, lang in enumerate(LANGS + ["en"]):
    layer = read_po(layer_dir / lang / "stereo-layer_qt.po") if lang != "en" else {}
    out = [header(lang)]
    for msgid in ids:
        if lang == "en":
            text = msgid
        elif msgid in T:
            text = T[msgid][index]
        elif msgid in layer and layer[msgid]:
            text = layer[msgid]
        else:
            missing.append((lang, msgid)); continue
        out.append('msgid "%s"\nmsgstr "%s"\n\n' % (esc(msgid), esc(text)))
    (po_dir / lang).mkdir(exist_ok=True)
    (po_dir / lang / "kcm_sparkystereo_camera.po").write_text("".join(out), encoding="utf-8")
if missing:
    for m in missing:
        print("MISSING", m)
    sys.exit(1)
print("ok", len(ids), "strings,", len(LANGS) + 1, "catalogues")
