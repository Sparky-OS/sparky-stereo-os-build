#!/usr/bin/env python3
"""Check renderer acceptance and the milestone's explicit asset contracts."""
import configparser
import json
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    svgs = sorted((ROOT / "share").rglob("*.svg"))
    results = []
    with tempfile.TemporaryDirectory(dir=ROOT / "rig", prefix="validate-") as temp:
        for number, path in enumerate(svgs):
            tree = ET.parse(path)
            ids = [e.attrib["id"] for e in tree.iter() if "id" in e.attrib]
            assert len(ids) == len(set(ids)), f"Duplicate SVG id: {path}"
            png = Path(temp) / f"{number}.png"
            subprocess.run(["rsvg-convert", str(path), "-o", str(png)], check=True)
            with Image.open(png) as image:
                assert image.getbbox(), f"Empty SVG render: {path}"
                if path.name == "decoration.svg":
                    assert image.getpixel((20, 6)) != image.getpixel((20, 7)), "Active stripes missing"
                    assert image.getpixel((20, 114)) == image.getpixel((20, 115)), "Inactive title is striped"
                    assert image.getpixel((20, 40))[3] == 0, "Decoration covers client contents"
                    assert {f"decoration{state}-{piece}" for state in ("", "-inactive") for piece in ("top", "topleft", "topright", "left", "center", "right", "bottom", "bottomleft", "bottomright")} <= set(ids)
                if path.name == "panel-background.svg" and "kubabbar-glass" in path.parts:
                    assert image.getpixel((20, 20))[3] == round(.91 * 255), "Panel centre alpha is not 91 percent"
            results.append(str(path.relative_to(ROOT)))
    config = configparser.ConfigParser()
    config.optionxform = str
    config.read(ROOT / "config/kwinrc")
    assert config["Effect-translucency"]["Inactive"] == "91"
    assert config["Effect-translucency"]["Dialogs"] == "91"
    assert config["Effect-translucency"]["ExcludeFullScreen"] == "true"
    assert config["Plugins"]["blurEnabled"] == "false"
    assert config["Plugins"]["contrastEnabled"] == "false"
    result = {"rendered_svg_files": results, "checks": ["Unique SVG IDs", "Nonempty librsvg renders", "Active stripes and plain inactive title", "Transparent decoration centre", "All Aurorae frame slices", "Panel centre alpha 232/255", "91 percent inactive and dialog settings", "Full screen exclusion and blur/contrast disabled"], "limitation": "These are asset and configuration checks, not evidence that KWin applies glass or stereo depth."}
    (ROOT / "evidence/asset-validation.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
