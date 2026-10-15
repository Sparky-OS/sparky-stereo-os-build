#!/usr/bin/env python3
"""Derive only Oxygen's background surfaces; inherit its other artwork unchanged."""
import gzip
import copy
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

SOURCE = Path("/usr/share/plasma/desktoptheme/oxygen")
ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "share/plasma/desktoptheme/sparky-stereo-oxygen"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
PARTS = {"center", "top", "bottom", "left", "right", "topleft", "topright", "bottomleft", "bottomright"}


def main():
    records = []
    for surface in ("widgets/background", "widgets/panel-background", "widgets/tooltip", "dialogs/background"):
        original = SOURCE / "solid" / (surface + ".svgz")
        if not original.exists():
            original = SOURCE / (surface + ".svgz")
        data = original.read_bytes()
        tree = ET.fromstring(gzip.decompress(data))
        indexed = {e.get("id"): e for e in tree.iter() if e.get("id")}
        defs = tree.find(f"{{{SVG}}}defs")
        def opaque_gradient(ident):
            new_id = "sparky-opaque-" + ident
            if new_id in indexed:
                return new_id
            clone = copy.deepcopy(indexed[ident])
            clone.set("id", new_id)
            for child in clone.iter():
                if child is not clone and child.get("id"):
                    child.set("id", "sparky-opaque-" + child.get("id"))
            indexed[new_id] = clone
            href = "{http://www.w3.org/1999/xlink}href"
            if clone.get(href, "").startswith("#"):
                clone.set(href, "#" + opaque_gradient(clone.get(href)[1:]))
            for stop in clone.iter(f"{{{SVG}}}stop"):
                style = re.sub(r"stop-opacity:[^;]+", "stop-opacity:1", stop.get("style", ""))
                stop.set("style", style)
                stop.set("stop-opacity", "1")
            defs.append(clone)
            return new_id
        frame_ids = []
        for parent in list(tree.iter()):
            for e in list(parent):
                tag = e.tag.split("}")[-1]
                if tag == "namedview":
                    parent.remove(e)
        for e in list(tree.iter()):
            for attr in list(e.attrib):
                if attr.split("}")[-1] in ("export-filename", "docname", "absref"):
                    del e.attrib[attr]
            ident = e.get("id", "")
            # Masks, shadows, hints and foreground/control artwork are not surfaces.
            if ident.split("-")[-1] in PARTS and not ident.startswith(("mask-", "shadow-")):
                if ident.split("-")[-1] == "center":
                    for child in e.iter():
                        style = child.get("style", "")
                        style = re.sub(r"fill:url\(#([^)]*)\)", lambda m: "fill:url(#" + opaque_gradient(m[1]) + ")", style)
                        child.set("style", style)
                style = re.sub(r"(^|;)opacity:[^;]*(;|$)", r"\1", e.get("style", ""))
                e.set("style", style.rstrip(";"))
                # Qt's fixed-point opacity maps this to 232/255, nearest to 91%.
                e.set("opacity", str(233 / 256))
                frame_ids.append(ident)
        assert any(i.split("-")[-1] == "center" for i in frame_ids), original
        xml = ET.tostring(tree, encoding="unicode") + "\n"
        assert not re.search(r"[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}", xml), "Source contact needs review"
        for variant in ("", "translucent", "solid", "opaque"):
            dest = TARGET / variant / (surface + ".svg")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(xml)
            records.append({"output": str(dest.relative_to(ROOT)), "source": str(original.relative_to(SOURCE)), "source_sha256": hashlib.sha256(data).hexdigest(), "frame_ids": frame_ids})
    # Plasma's alternate applet background must obey the same rule.
    for variant in ("", "translucent", "solid", "opaque"):
        (TARGET / variant / "widgets/translucentbackground.svg").write_text((TARGET / variant / "widgets/background.svg").read_text())
    meta = {"KPlugin": {"Id": "sparky-stereo-oxygen", "Name": "Sparky Stereo Oxygen", "Description": "Oxygen with 91 percent background alpha", "Authors": [{"Name": "The Oxygen Project"}, {"Name": "Daniel Ramos and EchoSystems AI studios"}], "License": "GPL", "Version": "20261014.1"}, "X-Plasma-API": "5.0"}
    (TARGET / "metadata.json").write_text(json.dumps(meta, indent=2) + "\n")
    (TARGET / "colors").write_bytes((SOURCE / "colors").read_bytes())
    (TARGET / "plasmarc").write_text("[Settings]\nFallbackTheme=oxygen\n[BlurBehindEffect]\nenabled=false\n[ContrastEffect]\nenabled=false\n[AdaptiveTransparency]\nenabled=false\n")
    (ROOT / "study/oxygen-derivation.json").write_text(json.dumps(records, indent=2) + "\n")


if __name__ == "__main__":
    main()
