#!/usr/bin/env python3
"""Check KWin's window rules independently of the Plasma SVG backgrounds."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence"


def main():
    records = []
    for theme in ("classic", "oxygen"):
        for mode in ("2d", "stereo"):
            folders = [EVIDENCE / f"windows-{theme}-{color}-{mode}" for color in ("black", "white")]
            for folder in folders:
                assert "FULLSCREEN_CONTROL=true" in (folder / "kwin.log").read_text()
                for name in ("support.txt", "fullscreen-support.txt"):
                    info = (folder / name).read_text()
                    assert "Compositing Type: OpenGL" in info
                    loaded = info.split("Loaded Effects:")[1].split("Currently Active Effects:")[0].splitlines()
                    assert "translucency" in loaded and "blur" not in loaded and "contrast" not in loaded
                for name in ("desktop.json", "fullscreen.json"):
                    metadata = json.loads((folder / name).read_text())
                    assert metadata["stereo"] == (mode == "stereo")
            for eye in (("LEFT.png", "RIGHT.png") if mode == "stereo" else ("desktop.png",)):
                images = [Image.open(folder / eye).convert("RGB") for folder in folders]
                result = {"theme": theme, "mode": mode, "eye": eye, "samples": []}
                for name, point, expected in (("inactive", (200,220), .91), ("dialog", (700,220), .91), ("active", (1000,650), 1)):
                    b, w = [im.getpixel(point) for im in images]
                    delta = [w[c] - b[c] for c in range(3)]
                    assert all(abs(d - (1-expected) * 255) <= 2 for d in delta), (theme, mode, eye, name, b, w)
                    result["samples"].append({"kind": name, "point": point, "black": b, "white": w, "measured_alpha": [round(1-d/255,6) for d in delta]})
                fullscreen = "fullscreen.png" if mode == "2d" else "fullscreen-" + eye
                b, w = [Image.open(folder / fullscreen).getpixel((800,500)) for folder in folders]
                assert b == w == (160,160,160), (theme, mode, eye, "fullscreen", b, w)
                result["fullscreen_pixel"] = b
                records.append(result)
    (EVIDENCE / "window-alpha.json").write_text(json.dumps(records, indent=2) + "\n")
    print(f"PASS: {len(records)} views; inactive/dialog 91%, active/fullscreen opaque, blur and contrast unloaded")


if __name__ == "__main__":
    main()
