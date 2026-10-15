#!/usr/bin/env python3
"""Measure eye disparity in actual captures, including foreground text."""
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]


def displacement(left, right, box):
    reference = left.crop(box)
    scores = []
    for offset in range(-12, 13):
        shifted = right.crop((box[0]+offset, box[1], box[2]+offset, box[3]))
        score = sum(ImageStat.Stat(ImageChops.difference(reference, shifted)).mean)
        scores.append((score, offset))
    score, offset = min(scores)
    return {"right_minus_left_pixels": offset, "mean_rgb_absolute_error": round(score/3, 6)}


def main():
    records = []
    for theme in ("classic", "oxygen"):
        for kind in ("alpha", "windows"):
            folder = ROOT / "evidence" / f"{kind}-{theme}-black-stereo"
            left, right = [Image.open(folder / eye).convert("RGB") for eye in ("LEFT.png", "RIGHT.png")]
            boxes = {"desktop widget": (790,490,1180,770), "widget text": (820,520,1120,570),
                     "panel popup": (20,700,335,925), "popup text": (40,710,300,750)} if kind == "alpha" else {
                     "inactive window": (65,70,515,405), "dialog": (580,70,1040,405), "active window": (680,420,1320,830)}
            for name, box in boxes.items():
                records.append({"theme": theme, "element": name, "box": box, **displacement(left, right, box)})
    (ROOT / "evidence/depth-measurements.json").write_text(json.dumps(records, indent=2) + "\n")
    for record in records:
        print(record)
    for theme in ("classic", "oxygen"):
        by_name = {r["element"]: r["right_minus_left_pixels"] for r in records if r["theme"] == theme}
        assert by_name["inactive window"] > 0 and by_name["desktop widget"] > 0
        assert by_name["active window"] == 0
        assert by_name["widget text"] == by_name["desktop widget"]
        assert by_name["popup text"] == by_name["panel popup"]
        assert by_name["panel popup"] < 0, (theme, "Popup did not pop", by_name)
    print("PASS: inactive/widget sunk, active at screen, popup popped, text at element depth")


if __name__ == "__main__":
    main()
