#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build a source-derived adapter, never a hand-transcribed depth formula."""
import argparse
import hashlib
import json
from pathlib import Path
import re

p = argparse.ArgumentParser()
p.add_argument("source", type=Path)
p.add_argument("output", type=Path)
a = p.parse_args()
source = a.source / "src/scene/stereodepth.cpp"
globals_file = a.source / "src/effect/globals.h"
s = source.read_text()
enum = re.search(r"enum class StereoEye\s*\{[^}]*\};", globals_file.read_text()).group()
reference = re.search(r"static constexpr qreal s_referenceWidth\s*=[^;]*;", s).group()


def operation(signature):
    start = s.index(signature)
    brace = s.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (s[end] == "{") - (s[end] == "}")
        end += 1
    return s[start:end]


functions = [operation("int StereoDepth::parallax(qreal depth, int viewWidth)"),
             operation("int StereoDepth::eyeShift(int parallax, StereoEye eye)")]
import xml.etree.ElementTree as ET
kcfg_file = a.source / "src/kwin.kcfg"
kcfg = ET.parse(kcfg_file)
defaults = {}
for entry in kcfg.iter():
    if entry.tag.rsplit('}', 1)[-1] == 'entry' and entry.get('name') in ('SunkLimit', 'PoppedLimit'):
        default = next(x.text for x in entry if x.tag.rsplit('}', 1)[-1] == 'default')
        defaults['Stereo' + entry.get('name')] = float(default)
if set(defaults) != {'StereoSunkLimit', 'StereoPoppedLimit'}:
    raise SystemExit('Cannot find the desktop depth defaults in KWin')
a.output.mkdir(parents=True, exist_ok=True)
(a.output / "desktop-depth.h").write_text(
    "// Generated from the recorded KWin source. SPDX-License-Identifier: GPL-2.0-or-later\n"
    "// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos\n"
    "#pragma once\n#include <QtCore/qglobal.h>\n#include <cmath>\nnamespace DesktopGeometry {\n" + enum + "\n" + reference +
    "\nclass StereoDepth { public: static int parallax(qreal, int); static int eyeShift(int, StereoEye); };\n" +
    "\n".join("inline " + f for f in functions) +
    ''.join(f'\ninline constexpr qreal {k} = {v};' for k, v in defaults.items()) + "\n}\n")
(a.output / "depth-source.json").write_text(json.dumps({
    "files": {str(x.relative_to(a.source)): hashlib.sha256(x.read_bytes()).hexdigest()
              for x in (source, globals_file, kcfg_file)}, "operations": functions}, indent=2) + "\n")
