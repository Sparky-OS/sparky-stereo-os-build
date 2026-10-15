#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Every window button SVG carries every state the decoration asks for, and each state draws something different where it should."""
import json
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from draw_theme import BUTTON_NAMES, BUTTON_STATES

DECO = ROOT / "share/aurorae/themes/kubabbar-glass"
QML = (ROOT / "share/kwin/decorations/kubabbar-glass/contents/ui/main.qml").read_text()


def main():
    report = {}
    with tempfile.TemporaryDirectory(dir=ROOT / "rig", prefix="buttons-") as temp:
        for name in BUTTON_NAMES:
            path = DECO / (name + ".svg")
            ids = {e.attrib["id"] for e in ET.parse(path).iter() if "id" in e.attrib}
            wanted = {("on-" if toggled else "") + state + "-center" for toggled in (False, True) for state in BUTTON_STATES}
            assert wanted <= ids, (name, wanted - ids)
            png = Path(temp) / (name + ".png")
            subprocess.run(["rsvg-convert", str(path), "-o", str(png)], check=True)
            sheet = Image.open(png).convert("RGBA")
            cells = {state: sheet.crop((i * 22, 0, i * 22 + 16, 16)).tobytes() for i, state in enumerate(BUTTON_STATES)}
            assert cells["active"] != cells["pressed"] != cells["inactive"], name
            assert cells["active"] != cells["hover"], name
            report[name] = "ok"
    for name in ("closeComponent", "maximizeComponent", "minimizeComponent", "allDesktopsComponent", "helpComponent", "menuComponent"):
        assert "id: " + name in QML, name
    assert "options.titleButtonsLeft" in QML and "options.titleButtonsRight" in QML
    kwinrc = (ROOT / "config/kwinrc").read_text()
    assert "ButtonsOnLeft=MS" in kwinrc and "ButtonsOnRight=HIAX" in kwinrc
    report["layout"] = "left MS (window menu, all desktops), right HIAX (help, minimize, maximize, close): KDE's default"
    (ROOT / "evidence/m2/buttons-check.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
