#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
"""Check ORDER 672's depth numbers against stereo-layer's actual source helper.

Usage: splash-depth-contract.py PATH/TO/src/quick/stereodepth.cpp
Run inside a container with a C++17 compiler. This source-level check compiles
the helper unchanged; it does not qualify the installed library or rendering.
The published 1.21.1 source fails the two double-popped rows.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    source = args.source.read_text()
    match = re.search(
        r"qreal Depth::parallaxFor\(qreal depth, qreal popped, qreal sunk, qreal viewWidth\)\s*\{",
        source,
    )
    if not match:
        parser.error("cannot find stereo-layer's parallaxFor implementation")
    start = match.end() - 1
    end = start + 1
    nesting = 1
    while nesting and end < len(source):
        nesting += (source[end] == "{") - (source[end] == "}")
        end += 1
    if nesting:
        parser.error("unterminated parallaxFor implementation")
    function = source[match.start():end]
    program = """#include <algorithm>
#include <cmath>
#include <iostream>
using qreal = double;
class Depth { public: static qreal parallaxFor(qreal, qreal, qreal, qreal); };
""" + function + """
int main() {
    double depth, popped, sunk, width;
    while (std::cin >> depth >> popped >> sunk >> width)
        std::cout << Depth::parallaxFor(depth, popped, sunk, width) << '\\n';
}
"""
    rows = [
        ("default background", -1, 4, 10, -10),
        ("default box", 1, 4, 10, 4),
        ("default logo", 2, 4, 10, 8),
        ("changed background", -1, 8, 20, -20),
        ("changed box", 1, 8, 20, 8),
        ("changed logo", 2, 8, 20, 16),
        ("zero background", -1, 0, 0, 0),
        ("zero box", 1, 0, 0, 0),
        ("zero logo", 2, 0, 0, 0),
    ]
    with tempfile.TemporaryDirectory(prefix="splash-depth-") as tmp:
        cpp = Path(tmp) / "probe.cpp"
        binary = Path(tmp) / "probe"
        cpp.write_text(program)
        subprocess.run([os.environ.get("CXX", "c++"), "-std=c++17", str(cpp), "-o", str(binary)], check=True)
        result = subprocess.run(
            [str(binary)],
            input="".join(f"{d} {p} {s} 1920\n" for _, d, p, s, _ in rows),
            text=True, capture_output=True, check=True,
        )
    actual = [float(x) for x in result.stdout.splitlines()]
    if len(actual) != len(rows):
        parser.error("helper returned an unexpected number of rows")
    failures = 0
    for (name, depth, popped, sunk, expected), value in zip(rows, actual):
        passed = value == expected
        failures += not passed
        print(json.dumps({"case": name, "depth": depth, "popped": popped,
                          "sunk": sunk, "width": 1920, "expected_parallax": expected,
                          "actual_parallax": value, "pass": passed}))
    print(f"{len(rows) - failures} passed, {failures} failed (source helper only)")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
