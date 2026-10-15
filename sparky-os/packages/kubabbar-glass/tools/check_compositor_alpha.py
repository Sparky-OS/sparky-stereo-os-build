#!/usr/bin/env python3
"""Measure real Plasma backgrounds using controlled black/white captures."""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence"
BACKGROUND = {
    "desktop widget": [(1100, 650), (1100, 710), (900, 570)],
    "panel popup": [(320, 845), (320, 895), (90, 850)],
    "panel": [(500, 965), (700, 975), (1200, 960)],
}
FOREGROUND = {
    "desktop icon": (865, 620), "popup icon": (70, 807),
    "desktop control": (930, 615), "popup control": (145, 800),
}


def main():
    records = []
    for theme in ("classic", "oxygen"):
        for mode in ("2d", "stereo"):
            folders = [EVIDENCE / f"alpha-{theme}-{color}-{mode}" for color in ("black", "white")]
            for folder in folders:
                support = (folder / "support.txt").read_text()
                assert "Compositing Type: OpenGL" in support
                loaded = support.split("Loaded Effects:")[1].split("Currently Active Effects:")[0].splitlines()
                assert "translucency" in loaded and "blur" not in loaded and "contrast" not in loaded
                metadata = json.loads((folder / "desktop.json").read_text())
                assert metadata["stereo"] == (mode == "stereo")
                assert metadata["width"] == (3200 if mode == "stereo" else 1600)
            for eye in (("LEFT.png", "RIGHT.png") if mode == "stereo" else ("desktop.png",)):
                black, white = [Image.open(f / eye).convert("RGB") for f in folders]
                assert black.getpixel((600, 300)) == (0, 0, 0)
                assert white.getpixel((600, 300)) == (255, 255, 255)
                result = {"theme": theme, "mode": mode, "eye": eye, "background": [], "foreground": []}
                for surface, points in BACKGROUND.items():
                    for point in points:
                        b, w = black.getpixel(point), white.getpixel(point)
                        delta = [w[c] - b[c] for c in range(3)]
                        # Match KWin's nearest representable alpha to 91 percent.
                        assert all(d == 255 - round(.91 * 255) for d in delta), (theme, mode, eye, surface, point, b, w)
                        result["background"].append({"surface": surface, "point": point, "black": b, "white": w,
                                                     "alpha": [round(1 - d / 255, 6) for d in delta]})
                for element, point in FOREGROUND.items():
                    b, w = black.getpixel(point), white.getpixel(point)
                    assert max(abs(b[c] - w[c]) for c in range(3)) <= 1, (theme, mode, eye, element, b, w)
                    result["foreground"].append({"element": element, "point": point, "black": b, "white": w})
                # Fully covered pink text pixels, excluding antialiasing edges.
                count = 0
                for y in range(510, 900):
                    for x in range(40, 1150):
                        b = black.getpixel((x, y))
                        if b == (236, 35, 97):
                            w = white.getpixel((x, y))
                            assert max(abs(b[c] - w[c]) for c in range(3)) <= 1, (theme, mode, eye, "Text changed", x, y, b, w)
                            count += 1
                assert count > 500, (theme, mode, eye, "Opaque text pixels missing", count)
                result["unchanged_text_pixels"] = count
                records.append(result)
    report = {"method": "alpha = 1 - (white minus black) / 255 per channel; require alpha 232/255, nearest to 91%",
              "scope": "Real Plasma applet, real panel popup and panel; no synthetic stereo duplication",
              "records": records}
    (EVIDENCE / "compositor-alpha.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(records)} views, 54 background samples, 24 icon/control samples, opaque text in every view")


if __name__ == "__main__":
    main()
