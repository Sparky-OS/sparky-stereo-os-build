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
# Sparky Black's levels, transplanted (Daniel, 2026-10-15: "both, kubabbar glass and stereo oxygen must carry the same
# transluscent configs every where (Sparky Black transluscent levels transplanted to both sparky stereo themes)"): the
# 8-bit alpha of each surface's centre as KSvg draws Sparky Black's Plasma style (queue row 125). A panel's level
# depends on its edge, as in Sparky Black; Oxygen's "thick" panel prefix, which Sparky Black lacks, takes the level
# KSvg falls back to there, the centre without a prefix. solid/ and opaque/ keep 232 (an Opaque panel, no compositing).
SPARKY_BLACK_ALPHA = {
    "widgets/panel-background": {"": 164, "thick": 164, "north": 44, "south": 129, "east": 44, "west": 44},
    "dialogs/background": {"": 157},
    "widgets/tooltip": {"": 157},
    "widgets/background": {"": 80},
    "widgets/translucentbackground": {"": 60},
}
SOLID_OPACITY = 233 / 256  # Qt's fixed-point opacity maps this to 232/255, nearest to 91%.


def painter_opacity(alpha):
    """The opacity Qt's 256-step painter turns into this 8-bit alpha: the smallest k/256 that it rounds to alpha,
    (255 * k + 128) // 256 == alpha (233/256 gives 232; checked by rendering with QSvgRenderer)."""
    k = next(k for k in range(257) if (255 * k + 128) // 256 == alpha)
    return k / 256


def main():
    records = []
    # Plasma's alternate applet background (translucentbackground) is Oxygen's applet background at its own level.
    for surface, output in (("widgets/background", "widgets/background"), ("widgets/panel-background", "widgets/panel-background"),
                            ("widgets/tooltip", "widgets/tooltip"), ("dialogs/background", "dialogs/background"),
                            ("widgets/background", "widgets/translucentbackground")):
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
                frame_ids.append(ident)
        assert any(i.split("-")[-1] == "center" for i in frame_ids), original
        frames = {e.get("id"): e for e in tree.iter() if e.get("id") in frame_ids}
        for variant in ("", "translucent", "solid", "opaque"):
            for ident, e in frames.items():
                prefix = ident.rsplit("-", 1)[0] if "-" in ident else ""
                level = SPARKY_BLACK_ALPHA[output]
                e.set("opacity", str(SOLID_OPACITY if variant in ("solid", "opaque") else painter_opacity(level[prefix])))
            xml = ET.tostring(tree, encoding="unicode") + "\n"
            assert not re.search(r"[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}", xml), "Source contact needs review"
            dest = TARGET / variant / (output + ".svg")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(xml)
            records.append({"output": str(dest.relative_to(ROOT)), "source": str(original.relative_to(SOURCE)), "source_sha256": hashlib.sha256(data).hexdigest(), "frame_ids": frame_ids})
    meta = {"KPlugin": {"Id": "sparky-stereo-oxygen", "Name": "Sparky Stereo Oxygen", "Description": "Oxygen with Sparky Black's translucency", "Authors": [{"Name": "The Oxygen Project"}, {"Name": "Daniel Ramos and EchoSystems AI studios"}], "License": "GPL", "Version": "20261126.1"}, "X-Plasma-API": "5.0"}
    (TARGET / "metadata.json").write_text(json.dumps(meta, indent=2) + "\n")
    (TARGET / "colors").write_bytes((SOURCE / "colors").read_bytes())
    (TARGET / "plasmarc").write_text("[Settings]\nFallbackTheme=oxygen\n[BlurBehindEffect]\nenabled=false\n[ContrastEffect]\nenabled=false\n[AdaptiveTransparency]\nenabled=false\n")
    (ROOT / "study/oxygen-derivation.json").write_text(json.dumps(records, indent=2) + "\n")


if __name__ == "__main__":
    main()
