#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Identify the encoder boundary with one FPA layout and both eye orders.

Run inside a disposable container with an explicitly authorized render node.
This measures SEI transport, not stereo image geometry or all codec profiles.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def nals(data):
    return [nal for nal in re.split(b"\x00\x00\x00?\x01", data)[1:] if nal]


def sei_messages(codec, data):
    for nal in nals(data):
        kind = nal[0] & 31 if codec == "h264" else (nal[0] >> 1) & 63
        if kind != (6 if codec == "h264" else 39):
            continue
        rbsp = nal[1 if codec == "h264" else 2:].replace(b"\0\0\3", b"\0\0")
        pos = 0
        while pos < len(rbsp) and rbsp[pos:] != b"\x80":
            values = []
            for _ in range(2):
                value = 0
                while pos < len(rbsp) and rbsp[pos] == 255:
                    value += 255
                    pos += 1
                assert pos < len(rbsp), "truncated SEI header"
                value += rbsp[pos]
                pos += 1
                values.append(value)
            kind, size = values
            assert pos + size <= len(rbsp), "truncated SEI payload"
            yield kind, rbsp[pos:pos + size]
            pos += size


def arrangement(payload):
    bits = "".join(f"{byte:08b}" for byte in payload)
    # Decode ue(v) id, then the fixed-width prefix (ITU-T H.264 D.1.26 /
    # H.265 D.2.16). The independent FFmpeg trace checks the remaining fields.
    zeros = bits.index("1")
    ident = int(bits[zeros:2 * zeros + 1], 2) - 1
    pos = 2 * zeros + 1
    cancel = int(bits[pos])
    assert not cancel, "cancellation is not this transport fixture"
    return {"id": ident, "type": int(bits[pos + 1:pos + 8], 2),
            "quincunx": int(bits[pos + 8]), "eye_order": int(bits[pos + 9:pos + 15], 2)}


def check(codec, stream, expected):
    actual = Path(stream).read_bytes()
    wanted = nals(Path(expected).read_bytes())
    assert len(wanted) == 1 and wanted[0] in nals(actual), "submitted NAL missing or changed"
    marks = [arrangement(payload) for kind, payload in sei_messages(codec, actual) if kind == 45]
    assert len(marks) == 1, f"expected one frame packing message, got {marks}"
    return marks[0]


def vcl(codec, data):
    if codec == "h264":
        return [nal for nal in nals(data) if 1 <= (nal[0] & 31) <= 5]
    return [nal for nal in nals(data) if ((nal[0] >> 1) & 63) <= 31]


def run(output):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    assert not list(output.iterdir()), "use a new, empty evidence directory"
    here = Path(__file__).resolve().parent
    env = os.environ.copy()
    env.pop("PROBE_SEI", None)
    env.pop("LD_PRELOAD", None)
    env["MESA_SHADER_CACHE_DISABLE"] = "true"

    def command(args, log, extra=None, expected=0):
        with (output / log).open("w") as f:
            result = subprocess.run(args, stdout=f, stderr=subprocess.STDOUT,
                                    env=env | (extra or {}), timeout=60, check=False)
        assert result.returncode == expected, f"{log}: exit {result.returncode}, expected {expected}"

    shim = output / "packed-sei.so"
    command(["gcc", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
             str(here / "vaapi-packed-sei.c"), "-o", str(shim), "-lva", "-ldl"], "compile.log")
    command(["vainfo", "--display", "drm", "--device", "/dev/dri/renderD128"], "driver.log")
    command(["ffmpeg", "-version"], "ffmpeg-version.log")
    command(["dpkg-query", "-W", "mesa-va-drivers", "libva2", "ffmpeg", "gcc", "libva-dev"], "packages.log")
    source = output / "source.h264"
    command(["ffmpeg", "-hide_banner", "-y", "-f", "lavfi", "-i",
             "color=red:size=960x1080:rate=30[l];color=blue:size=960x1080:rate=30[r];[l][r]hstack",
             "-frames:v", "1", "-c:v", "libx264", "-threads", "2", "-x264-params", "frame-packing=3",
             "-f", "h264", str(source)], "source.log")
    assert any(kind == 45 for kind, _ in sei_messages("h264", source.read_bytes()))
    rows = []
    for codec in ("h264", "hevc"):
        base = output / f"baseline.{codec}"
        encode = ["ffmpeg", "-hide_banner", "-y", "-vaapi_device", "/dev/dri/renderD128",
                  "-threads", "2", "-i", str(source), "-filter_threads", "1",
                  "-vf", "showinfo,format=nv12,hwupload", "-frames:v", "1", "-c:v", f"{codec}_vaapi",
                  "-rc_mode", "CQP", "-qp", "23", "-bf", "0", "-f", codec]
        command(encode + [str(base)], f"baseline-{codec}.log", {"LD_PRELOAD": str(shim)})
        base_log = (output / f"baseline-{codec}.log").read_text()
        assert "side data - Stereo 3D: type - side by side" in base_log
        assert not any(kind == 45 for kind, _ in sei_messages(codec, base.read_bytes()))
        client_data = b"".join(bytes.fromhex(h) for h in re.findall(r"probe: client .* bytes=([0-9a-f]+)", base_log))
        assert not any(kind == 45 for kind, _ in sei_messages(codec, client_data))
        command(["ffmpeg", "-hide_banner", "-i", str(base), "-vf", "showinfo", "-f", "null", "-"],
                f"baseline-{codec}-decode.log")
        assert "side data - Stereo 3D" not in (output / f"baseline-{codec}-decode.log").read_text()
        for eye in (1, 2):
            # id=0, cancel=0, type=3, quincunx=0, content_interpretation_type=eye,
            # remaining flags/grid/reserved=0, repetition_period=0 (AVC) or
            # persistence=0 (HEVC), extension/upsampled_aspect_ratio=0.
            rbsp = bytes.fromhex("2d0681") + bytes([0x80 | eye]) + bytes.fromhex("00000300")
            rbsp += bytes([2 if codec == "h264" else 0, 0x80])
            nal = bytes.fromhex("00000001") + (b"\x06" if codec == "h264" else b"\x4e\x01") + rbsp
            name = f"{codec}-sbs-eye{eye}"
            expected = output / f"{name}.nal"
            expected.write_bytes(nal)
            marked = output / f"{name}.{codec}"
            command(encode + [str(marked)], f"{name}-encode.log",
                    {"LD_PRELOAD": str(shim), "PROBE_SEI": str(expected)})
            assert "submitted picture=1 status=0" in (output / f"{name}-encode.log").read_text()
            fields = check(codec, marked, expected)
            assert fields == {"id": 0, "type": 3, "quincunx": 0, "eye_order": eye}
            assert vcl(codec, base.read_bytes()) == vcl(codec, marked.read_bytes()), "coded picture changed"
            command(["ffmpeg", "-hide_banner", "-i", str(marked), "-vf", "showinfo", "-f", "null", "-"],
                    f"{name}-decode.log")
            line = next(line for line in (output / f"{name}-decode.log").read_text().splitlines()
                        if "side data - Stereo 3D" in line)
            assert "side by side" in line and ("inverted" in line) == (eye == 2)
            command(["ffmpeg", "-hide_banner", "-i", str(marked), "-c", "copy", "-bsf:v", "trace_headers",
                     "-f", "null", "-"], f"{name}-headers.log")
            trace = (output / f"{name}-headers.log").read_text()
            assert re.search(r"content_interpretation_type\s+[01]+ = " + str(eye), trace)
            command([sys.executable, str(Path(__file__).resolve()), "--check", codec, str(base), str(expected)],
                    f"{name}-negative.log", expected=1)
            rows.append({"codec": codec, "eye_order": eye, "fields": fields,
                         "byte_exact": True, "vcl_unchanged": True, "decode": line.strip(),
                         "negative_exit": 1})
            if codec == "hevc":
                constraints = sorted({int(value) for value in re.findall(
                    r"general_non_packed_constraint_flag\s+[01]+ = ([01])", trace)})
                assert constraints, "HEVC profile constraints were not inspected"
                rows[-1]["general_non_packed_constraint_flags"] = constraints
                rows[-1]["conformance_warning"] = (
                    "The client's non-packed constraint conflicts with the added FPA; "
                    "this is a transport diagnostic, not a conforming encoder fix."
                    if 1 in constraints else None)
    (output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    print(json.dumps(rows, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--run", type=Path)
    group.add_argument("--check", nargs=3, metavar=("CODEC", "STREAM", "EXPECTED_NAL"))
    args = parser.parse_args()
    if args.run:
        run(args.run)
    else:
        print(json.dumps(check(*args.check)))
