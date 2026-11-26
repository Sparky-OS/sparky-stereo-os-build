#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""verdicts.py RESULTS ROLE [--baseline FOLDER] -- one row per claim of the paper depth proof; exit 1 when a row fails.

ROLE staged: the desk one element step behind the window, the paper at the window's plane (parallax -1 at the shipped
element limit of 1 on a view 1920 wide, -12 at the measuring scale of 12), equal eyes at an element limit of 0 and in
presentation mode, a background window flat inside (its paper and desk at one level), a page run under the toolbar cut
at the window's plane. ROLE published: no step anywhere (the desk at the paper's level). ROLE kwin-older: the staged
Qt and Okular on a Stereo KWin older than version 7: no step, and each program's log says why. With --baseline, a 2D screen
shows the same pixels as the baseline's run (published) of the same case.
"""
import json
import os
import sys

results, role = sys.argv[1], sys.argv[2]
baseline = sys.argv[sys.argv.index("--baseline") + 1] if "--baseline" in sys.argv else None
rows = []


def row(name, ok, measured, expected):
    rows.append((name, ok, measured, expected))


def load(case, name="measure.json"):
    try:
        with open(os.path.join(results, case, name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def shifts(m, key):
    return [e[key]["shift"] if e.get(key) else None for e in m.get("measures", [])]


for kind in ("okular", "preview"):
    for case, step in ((f"{kind}-3d", -1), (f"{kind}-scale12", -12)):
        m = load(case)
        if not m:
            row(case, False, "no measurement", "measured")
            continue
        paper, desk = shifts(m, "paper"), shifts(m, "desk")
        expected_desk = step if role == "staged" else 0
        row(f"{case} pages found", len(paper) >= 2, len(paper), ">= 2")
        row(f"{case} paper at the window's plane", bool(paper) and all(s == 0 for s in paper), paper, 0)
        row(f"{case} desk", bool(desk) and all(s == expected_desk for s in desk if s is not None) and any(s is not None for s in desk),
            desk, expected_desk)
        title = (m.get("title_bar") or {}).get("shift")
        row(f"{case} title bar at the window's plane", title == 0, title, 0)
    m = load(f"{kind}-limit0")
    row(f"{kind}-limit0 equal eyes", bool(m) and m.get("stereo") and m.get("differing") == 0,
        m and m.get("differing"), 0)
    m = load(f"{kind}-scrolled")
    if m:
        cut = [e for e in m.get("measures", []) if e.get("paper_at_cut")]
        row(f"{kind}-scrolled a page under the toolbar", bool(cut), len(cut), ">= 1")
        for e in cut:
            row(f"{kind}-scrolled page {e['page']} at the cut at the window's plane", e["paper_at_cut"]["shift"] == 0,
                e["paper_at_cut"]["shift"], 0)
            edges = e.get("right_edge_at_cut") or [None, None]
            row(f"{kind}-scrolled page {e['page']} right edge at the cut, both eyes", edges[0] is not None and edges[0] == edges[1],
                edges, "equal columns")
    else:
        row(f"{kind}-scrolled", False, "no measurement", "measured")
    m = load(f"{kind}-background")
    if m and m.get("measures"):
        e = m["measures"][0]
        paper = (e.get("paper") or {}).get("shift")
        desk = (e.get("desk") or {}).get("shift")
        title = (m.get("title_bar") or {}).get("shift")
        row(f"{kind}-background flat inside (paper, desk, title bar at one level)",
            paper is not None and paper == desk == title, [paper, desk, title], "one level")
    else:
        row(f"{kind}-background", False, "no measurement", "measured")
    if baseline:
        b = load(f"{kind}-2d", "baseline.json")
        row(f"{kind}-2d same pixels as the baseline", bool(b) and b.get("differing") == 0, b and b.get("differing"), 0)
    m = load(f"{kind}-2d")
    row(f"{kind}-2d a 2D capture", bool(m) and not m.get("stereo"), m and m.get("capture"), "one picture")
if role == "kwin-older":
    for kind in ("okular", "preview"):
        try:
            with open(os.path.join(results, f"{kind}-3d", "program.err"), errors="replace") as f:
                said = sum(1 for line in f if "kde_stereo_depth_v1 version 7" in line)
        except OSError:
            said = None
        row(f"{kind}-3d says why it is flat", said == 1, said, "one log line")
m = load("okular-presentation")
row("okular-presentation equal eyes", bool(m) and m.get("stereo") and m.get("differing") == 0, m and m.get("differing"), 0)

failed = 0
for name, ok, measured, expected in rows:
    failed += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {name}: {json.dumps(measured)} (expected {expected})")
print(f"{len(rows) - failed} of {len(rows)} rows as expected ({role})")
sys.exit(1 if failed else 0)
