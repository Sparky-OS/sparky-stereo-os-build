#!/usr/bin/env python3
"""Render named slices through QtSvg, the SVG renderer used underneath KSvg."""
import json
import os
import xml.etree.ElementTree as ET
from pathlib import Path
os.environ["QT_QPA_PLATFORM"] = "offscreen"
from PySide6.QtGui import QGuiApplication, QImage, QPainter
from PySide6.QtCore import QRectF
from PySide6.QtSvg import QSvgRenderer

ROOT = Path(__file__).resolve().parents[1]


def main():
    app = QGuiApplication([])
    records = []
    for theme in ("kubabbar-glass", "sparky-stereo-oxygen"):
        for path in sorted((ROOT / "share/plasma/desktoptheme" / theme).rglob("*.svg")):
            r = QSvgRenderer(str(path))
            assert r.isValid(), path
            for element in ET.parse(path).iter():
                name = element.get("id", "")
                if name.split("-")[-1] != "center" or name.startswith(("shadow-", "mask-")):
                    continue
                image = QImage(64, 64, QImage.Format_RGBA8888)
                image.fill(0)
                painter = QPainter(image)
                r.render(painter, name, QRectF(0, 0, 64, 64))
                painter.end()
                alpha = image.pixelColor(32, 32).alpha()
                records.append({"file": str(path.relative_to(ROOT)), "id": name, "alpha": alpha})
    (ROOT / "evidence/frame-alpha.json").write_text(json.dumps(records, indent=2) + "\n")
    failures = [r for r in records if r["alpha"] != round(.91 * 255)]
    print(f"{len(records)} named centre slices, {len(failures)} failures")
    print(json.dumps(failures, indent=2))
    assert not failures


if __name__ == "__main__":
    main()
