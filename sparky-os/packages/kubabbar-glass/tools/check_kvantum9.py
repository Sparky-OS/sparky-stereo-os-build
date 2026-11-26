#!/usr/bin/env python3
"""check_kvantum9.py DEFAULT_SVG: check Kubabbar Glass 9's Kvantum themes before they ship.
- Every id that Kvantum's own default theme (doc/default.svg of the Kvantum source) has for an element family these
  themes use is in each of our SVGs: Kvantum draws a missing element, and a missing -disabled state, from its default
  artwork, so a gap shows foreign drawings in a person's programs.
- Every element of ours renders at its full pixel size: QSvgRenderer's bounds of each group equal its invisible
  bounding rectangle, so Kvantum scales nothing by an edge pixel.
- Every element name a configuration section asks for exists in normal and disabled states.
- The "Apart" configurations differ from the "together" ones only in scroll_arrows_together and their comments.
GPL-3.0-only."""
import configparser
import re
import sys
from pathlib import Path

from PyQt6.QtGui import QGuiApplication
from PyQt6.QtSvg import QSvgRenderer

ROOT = Path(__file__).resolve().parents[1] / "share/Kvantum"
FAMILIES = ("button", "checkbox", "radio", "arrow", "scrollbarslider", "slider", "slidercursor", "progress", "tab",
            "tabframe", "menu", "menuitem", "menubaritem", "tooltip", "lineedit", "spin", "itemview", "toolbar", "dock",
            "splitter", "sizegrip", "titlebar", "mdi", "grip", "focus", "group", "common", "dial", "header")


def ids(path):
    return set(re.findall(r'<g id="([^"]+)"', Path(path).read_text())) | set(
        i for i in re.findall(r'\bid="([^"]+)"', Path(path).read_text()))


def main():
    app = QGuiApplication(sys.argv[:1])  # noqa: F841 (QSvgRenderer needs an application)
    default_ids = {i for i in ids(sys.argv[1]) if re.match(r"^[a-z]", i)}
    wanted = {i for i in default_ids if i.split("-")[0] in FAMILIES}
    problems = []
    svgs = sorted(p for p in ROOT.glob("KubabbarGlass9*/*.svg") if not p.is_symlink())
    for svg in svgs:
        ours = set(re.findall(r'<g id="([^"]+)"', svg.read_text()))
        missing = sorted(wanted - ours)
        if missing:
            problems.append(f"{svg.name}: {len(missing)} ids of Kvantum's default artwork missing: {missing[:12]}")
        renderer = QSvgRenderer(str(svg))
        if not renderer.isValid():
            problems.append(f"{svg.name}: not a valid SVG for Qt")
            continue
        text = svg.read_text()
        for m in re.finditer(r'<g id="([^"]+)"><rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" fill="#000000" fill-opacity="0"/>', text):
            eid, x, y, w, h = m.group(1), *map(int, m.groups()[1:])
            b = renderer.boundsOnElement(eid)
            if (round(b.x()), round(b.y()), round(b.width()), round(b.height())) != (x, y, w, h):
                problems.append(f"{svg.name}: {eid} bounds {b} instead of {x},{y} {w}x{h}")
        # the elements each section asks for
        conf = configparser.ConfigParser(interpolation=None, strict=False)
        conf.optionxform = str
        conf.read(svg.with_suffix(".kvconfig"))
        for sec in conf.sections():
            s = conf[sec]
            for key, kind in (("frame.element", "frame"), ("interior.element", "interior")):
                el = s.get(key)
                on = s.get("frame" if kind == "frame" else "interior", "true") != "false"
                if not el or not on:
                    continue
                for state in ("normal", "disabled"):
                    name = f"{el}-{state}" + ("-top" if kind == "frame" and s.get("frame.top", "1") != "0" else "")
                    if kind == "frame" and name not in ours:
                        name = f"{el}-{state}-left"
                    if name not in ours:
                        problems.append(f"{svg.name} [{sec}]: {name} missing")
    for apart in sorted(ROOT.glob("KubabbarGlass9*Apart/*.kvconfig")):
        together = ROOT / apart.parent.name[:-len("Apart")] / (apart.parent.name[:-len("Apart")] + ".kvconfig")
        a = [l for l in apart.read_text().splitlines() if not l.startswith(("comment", "scroll_arrows_together"))]
        t = [l for l in together.read_text().splitlines() if not l.startswith(("comment", "scroll_arrows_together"))]
        if a != t:
            problems.append(f"{apart.name} differs from {together.name} beyond the arrows")
        link = apart.with_suffix(".svg")
        if not link.is_symlink() or link.resolve() != together.with_suffix(".svg").resolve():
            problems.append(f"{link.name} does not link {together.with_suffix('.svg').name}")
    print(f"{len(svgs)} SVGs, {len(wanted)} default ids of the used families each; {len(problems)} problems")
    for p in problems:
        print(" ", p)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
