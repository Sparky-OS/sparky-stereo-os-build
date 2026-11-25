#!/usr/bin/env python3
"""Regenerate measured weak native loops from the accepted weather theme export."""
import csv
import gzip
from math import cos, tau
from pathlib import Path
import struct
from subprocess import run
import sys
from tempfile import TemporaryDirectory
import xml.etree.ElementTree as ET

SVG = "http://www.w3.org/2000/svg"
STEREO = "https://github.com/Sparky-OS/svgstereo"
ET.register_namespace("", SVG)
ET.register_namespace("stereo", STEREO)


def xmp(data):
    offset = 0
    while offset < len(data):
        size, kind = struct.unpack_from(">I4s", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Unexpected source box size")
        if kind == b"xml ":
            payload = data[offset + 8:offset + size]
            if b"sideBySideLeftFirst" in payload:
                return payload
        offset += size
    raise ValueError("Missing JXLStereo packet")


def vector(source, target):
    root = ET.fromstring(gzip.decompress(source.read_bytes()))
    assert root.attrib[f"{{{STEREO}}}layout"] == "sideBySideLeftFirst"
    frames = [element for element in root if element.get("id", "").startswith("frame-")]
    assert len(frames) == 12
    for i, frame in enumerate(frames):
        beat = (1.0 - cos(tau * i / len(frames))) / 2.0
        # Keep the per-eye projections and the existing discrete frame timeline.
        for group in frame.findall(f"{{{SVG}}}g"):
            group.set("opacity", f"{1.0 - 0.58 * beat:.6f}")
            for shape in group.iter():
                colour = shape.get("fill", "")
                if len(colour) == 7 and colour.startswith("#"):
                    samples = (int(colour[i:i + 2], 16) for i in (1, 3, 5))
                    exposure = 1.0 - 0.72 * beat
                    shape.set("fill", "#" + "".join(f"{round(sample * exposure):02x}" for sample in samples))
    target.write_bytes(gzip.compress(ET.tostring(root, encoding="utf-8", xml_declaration=True), mtime=0))


def main(before, after, selected, encoder, proof):
    with selected.open() as listing, TemporaryDirectory() as temporary:
        packet = Path(temporary) / "packet.xml"
        for row in csv.DictReader(listing, delimiter="\t"):
            theme, name, side = (row[field] for field in ("theme", "name", "size"))
            ext = "svgz" if "vector" in theme else "jxl"
            relative = Path(theme) / "stereo" / f"{side}x{side}" / "status" / f"{name}.loop.{ext}"
            source, target = before / relative, after / relative
            print(relative, flush=True)
            # Input and output trees may share hardlinks with the accepted payload.
            sibling = target.with_name(f"new.{target.name}")
            if ext == "svgz":
                vector(source, sibling)
            else:
                packet.write_bytes(xmp(source.read_bytes()))
                mode = {"weather-clear-night": "moon"}.get(name, "symbolic" if name.endswith("-symbolic") else "pulse")
                sample = str(proof / theme / name / side) if theme == "sparky-weather-real" and side in ("22", "64") and name.startswith("weather-clear-night") else ""
                run([encoder, source, sibling, packet, mode, sample], check=True)
            sibling.replace(target)


if __name__ == "__main__":
    main(*map(Path, sys.argv[1:]))
