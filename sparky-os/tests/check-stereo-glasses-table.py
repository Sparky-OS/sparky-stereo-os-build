#!/usr/bin/env python3
"""The identity table of the USB-C 3D glasses agrees with Stereo KWin and with the glasses' real EDIDs.

One file, two readers: sparky-os/data/stereo-glasses.json is read by Stereo KWin at build time and embedded
by the Windows glasses keeper. This check reads the table, KWin's shipped identity table
(src/outputconfigurationstore.cpp, s_stereoGlasses[]), KWin's mock glasses test (the mode lists each state
announces, and the EDID files it reads) and the real EDIDs (autotests/integration/data/*.bin, or *.hex as rows of hex),
and fails when any two disagree on an identity or a mode. Every state of an entry is either backed by an EDID or listed
under not_public with its reason; the controls and the identities not entered must never reach KWin's table.

Usage: check-stereo-glasses-table.py [--table FILE] [--kwin DIR] [--keeper-table FILE]
  --kwin DIR          a KWin source tree carrying the glasses commits (default: the kwin/ folder of this tree)
  --keeper-table FILE the Windows keeper's embedded copy of the table; when given, it must be byte-identical

EDID fields follow VESA E-EDID Standard Release A, Revision 2: 3.4 (vendor and product identification),
3.10.2 (detailed timing descriptor), 3.10.3 (monitor descriptors, tag 0xFC the monitor name), 3.11 (checksum).
"""

import argparse
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TREE = os.path.dirname(os.path.dirname(HERE))

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL: " + msg)


def ok(msg):
    print("ok: " + msg)


def read_edid(path):
    data = open(path, "rb").read()
    if path.endswith(".hex"):
        data = bytes.fromhex(data.decode("ascii"))
    return data


def decode_edid(data):
    if len(data) < 128:
        raise ValueError("EDID shorter than 128 bytes")
    if data[0:8] != bytes([0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0]):
        raise ValueError("bad EDID header")
    if sum(data[0:128]) % 256 != 0:
        raise ValueError("bad EDID checksum")
    word = (data[8] << 8) | data[9]
    maker = "".join(chr(0x40 + ((word >> shift) & 0x1F)) for shift in (10, 5, 0))
    product = data[10] | (data[11] << 8)
    serial = int.from_bytes(data[12:16], "little")
    week, year = data[16], 1990 + data[17]
    version = (data[18], data[19])
    name = None
    timings = []
    # the base block's four descriptors, then the detailed timings of every CTA-861 extension the base block declares
    # (byte 126; CTA-861 7.5: byte 2 gives the offset of the first detailed timing, 0 or 4 when there is none)
    places = [(0, range(54, 126, 18))]
    for block in range(1, 1 + data[126]):
        start = 128 * block
        if len(data) < start + 128:
            raise ValueError("EDID declares %d extensions, has %d" % (data[126], len(data) // 128 - 1))
        if sum(data[start:start + 128]) % 256 != 0:
            raise ValueError("bad checksum in block %d" % block)
        if data[start] == 0x02 and data[start + 2] > 4:
            places.append((block, range(start + data[start + 2], start + 127 - 17, 18)))
    for block, offsets in places:
        for off in offsets:
            d = data[off:off + 18]
            clock = d[0] | (d[1] << 8)
            if clock != 0:
                hactive = d[2] | ((d[4] >> 4) << 8)
                hblank = d[3] | ((d[4] & 0x0F) << 8)
                vactive = d[5] | ((d[7] >> 4) << 8)
                vblank = d[6] | ((d[7] & 0x0F) << 8)
                pixel_hz = clock * 10000
                refresh = pixel_hz / ((hactive + hblank) * (vactive + vblank))
                timings.append({"width": hactive, "height": vactive, "refresh_hz": round(refresh, 3)})
            elif block == 0 and d[3] == 0xFC:
                name = d[5:18].split(b"\x0a")[0].decode("ascii").strip()
    return {"maker": maker, "product": product, "serial": serial, "week": week, "year": year,
            "version": version, "name": name, "timings": timings}


def kwin_identity_table(kwin):
    path = os.path.join(kwin, "src", "outputconfigurationstore.cpp")
    text = open(path, encoding="utf-8").read()
    m = re.search(r"s_stereoGlasses\[\]\s*=\s*\{(.*?)\};", text, re.S)
    if not m:
        raise ValueError("s_stereoGlasses[] not found in " + path)
    entries = re.findall(r'\{\s*"([A-Z]{3})"\s*,\s*0x([0-9a-fA-F]+)\s*\}', m.group(1))
    return {(maker, int(product, 16)) for maker, product in entries}


def kwin_test_text(kwin):
    return open(os.path.join(kwin, "autotests", "drm", "mockGlassesTest.cpp"), encoding="utf-8").read()


def kwin_mode_lists(kwin):
    path = os.path.join(kwin, "autotests", "drm", "mockGlassesTest.cpp")
    text = open(path, encoding="utf-8").read()
    lists = {}
    for name in ("s_sideBySideModes", "s_flatModes", "s_realDModes"):
        m = re.search(name + r"\{(.*?)\};", text, re.S)
        if not m:
            raise ValueError(name + " not found in " + path)
        lists[name] = [(int(w), int(h), float(r)) for w, h, r in
                       re.findall(r"\{\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\}", m.group(1))]
    return lists


def table_modes(state):
    out = []
    for mode in state["modes"]:
        for hz in mode["refresh_hz"]:
            out.append((mode["width"], mode["height"], float(hz)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", default=os.path.join(TREE, "sparky-os", "data", "stereo-glasses.json"))
    ap.add_argument("--kwin", default=os.path.join(TREE, "kwin"))
    ap.add_argument("--keeper-table", default=None)
    args = ap.parse_args()

    if not os.path.exists(args.table):
        fail("identity table missing: " + args.table)
        return finish()
    with open(args.table, encoding="utf-8") as f:
        table = json.load(f)
    if table.get("format") != "sparky-stereo-glasses":
        fail("table format is %r, expected sparky-stereo-glasses" % table.get("format"))
    glasses = table.get("glasses", [])
    if not glasses:
        fail("the table lists no glasses")

    try:
        kwin_ids = kwin_identity_table(args.kwin)
        ok("KWin identity table: " + ", ".join("%s 0x%04x" % g for g in sorted(kwin_ids)))
    except (OSError, ValueError) as e:
        fail("KWin identity table unreadable: %s" % e)
        kwin_ids = None
    try:
        kwin_modes = kwin_mode_lists(args.kwin)
    except (OSError, ValueError) as e:
        fail("KWin mock glasses test unreadable: %s" % e)
        kwin_modes = None

    try:
        test_text = kwin_test_text(args.kwin)
    except OSError as e:
        fail("KWin mock glasses test unreadable: %s" % e)
        test_text = None
    data_dir = os.path.join(args.kwin, "autotests", "integration", "data")

    table_ids = set()
    for g in glasses:
        maker, product = g["maker"], int(g["product"], 16)
        table_ids.add((maker, product))
        panel = g["panel_per_eye"]
        states = {s["state"]: s for s in g["states"]}
        not_public = g.get("not_public", {})
        if "2d" not in states and not states:
            fail("%s: no state backed by an EDID" % g["name"])
        for required in ("2d", "half", "full"):
            if required in states and required in not_public:
                fail("%s: state %r is both measured and listed as not public" % (g["name"], required))
            elif required not in states and required not in not_public:
                fail("%s: state %r missing and not listed under not_public" % (g["name"], required))
        for s in g["states"]:
            edid_path = os.path.join(data_dir, s["edid"])
            try:
                edid = decode_edid(read_edid(edid_path))
            except (OSError, ValueError) as e:
                fail("%s %s: EDID %s unreadable: %s" % (g["name"], s["state"], s["edid"], e))
                continue
            if (edid["maker"], edid["product"]) != (maker, product):
                fail("%s %s: EDID identity %s 0x%04x, table says %s 0x%04x"
                     % (g["name"], s["state"], edid["maker"], edid["product"], maker, product))
            if edid["name"] != g["name"]:
                fail("%s %s: EDID name %r, table says %r" % (g["name"], s["state"], edid["name"], g["name"]))
            if edid["serial"] != g.get("serial", 0):
                fail("%s %s: EDID serial %d, table says %d" % (g["name"], s["state"], edid["serial"], g.get("serial", 0)))
            if "edid_version" in g and "%d.%d" % edid["version"] != g["edid_version"]:
                fail("%s %s: EDID version %d.%d, table says %s" % (g["name"], s["state"], *edid["version"], g["edid_version"]))
            made = s.get("made", g.get("made"))
            if made and (edid["week"], edid["year"]) != (made["week"], made["year"]):
                fail("%s %s: EDID made week %d of %d, table says week %d of %d"
                     % (g["name"], s["state"], edid["week"], edid["year"], made["week"], made["year"]))
            if test_text is not None and not g.get("kwin_mock_lists") and '"%s"' % s["edid"] not in test_text:
                fail("%s %s: KWin's mock glasses test does not read %s" % (g["name"], s["state"], s["edid"]))
            edid_modes = []
            for t in edid["timings"]:
                mode = (t["width"], t["height"], round(t["refresh_hz"]))
                if mode not in edid_modes:
                    edid_modes.append(mode)
            want = [(w, h, round(r)) for w, h, r in table_modes(s)]
            if edid_modes != want:
                fail("%s %s: EDID timings %s, table says %s" % (g["name"], s["state"], edid_modes, want))
            else:
                ok("%s %s: table modes equal the EDID's detailed timings %s" % (g["name"], s["state"], want))
            first = edid["timings"][0]
            full = first["width"] == 2 * panel["width"]
            if s["state"] == "full" and not full:
                fail("%s full: first timing %d wide is not twice the panel's %d" % (g["name"], first["width"], panel["width"]))
            if s["state"] in ("2d", "half", "realD") and first["width"] != panel["width"]:
                fail("%s %s: first timing %d wide is not the panel's %d" % (g["name"], s["state"], first["width"], panel["width"]))
            if s["state"] == "realD" and s.get("stereo") is not False:
                fail("%s realD: the glasses' own Real 3D is 2D to the computer; stereo must be false" % g["name"])
            if s["state"] == "half" and "2d" in states and table_modes(states["2d"]) != table_modes(s):
                fail("%s half: the half dump is byte-identical to 2D, so the modes must be equal" % g["name"])
        if kwin_modes is not None and g.get("kwin_mock_lists"):
            pairs = (("full", "s_sideBySideModes"), ("2d", "s_flatModes"), ("half", "s_flatModes"), ("realD", "s_realDModes"))
            for state, kwin_name in pairs:
                if state not in states:
                    continue
                if table_modes(states[state]) != kwin_modes[kwin_name]:
                    fail("%s %s: table modes %s, KWin's %s says %s"
                         % (g["name"], state, table_modes(states[state]), kwin_name, kwin_modes[kwin_name]))
                else:
                    ok("%s %s: table modes equal KWin's %s" % (g["name"], state, kwin_name))

    for c in table.get("controls", []):
        ident = (c["maker"], int(c["product"], 16))
        try:
            edid = decode_edid(read_edid(os.path.join(data_dir, c["edid"])))
        except (OSError, ValueError) as e:
            fail("control %s: EDID %s unreadable: %s" % (c["name"], c["edid"], e))
            continue
        if (edid["maker"], edid["product"], edid["name"]) != (ident[0], ident[1], c["name"]):
            fail("control %s: EDID says %s 0x%04x %r" % (c["name"], edid["maker"], edid["product"], edid["name"]))
        if kwin_ids is not None and ident in kwin_ids:
            fail("control %s %s 0x%04x is in KWin's glasses table" % (c["name"], *ident))
        elif test_text is not None and '"%s"' % c["edid"] not in test_text:
            fail("control %s: KWin's mock glasses test does not read %s" % (c["name"], c["edid"]))
        else:
            ok("control %s %s 0x%04x: not glasses, and tested" % (c["name"], *ident))
    for n in table.get("not_entered", []):
        ident = (n["maker"], int(n["product"], 16))
        if ident in table_ids or (kwin_ids is not None and ident in kwin_ids):
            fail("%s %s 0x%04x is listed as not entered, yet it is in the table or in KWin" % (n["name"], *ident))
        else:
            ok("%s %s 0x%04x stays out: %s" % (n["name"], *ident, n["why"]))

    if kwin_ids is not None:
        if table_ids != kwin_ids:
            fail("identities differ: table %s, KWin %s" % (sorted(table_ids), sorted(kwin_ids)))
        else:
            ok("the table and KWin carry the same identities")

    if args.keeper_table:
        a = hashlib.sha256(open(args.table, "rb").read()).hexdigest()
        b = hashlib.sha256(open(args.keeper_table, "rb").read()).hexdigest()
        if a != b:
            fail("the keeper's embedded table differs from the tree's (sha256 %s vs %s)" % (a[:12], b[:12]))
        else:
            ok("the keeper's embedded table is byte-identical to the tree's (sha256 %s)" % a[:12])
    return finish()


def finish():
    if failures:
        print("%d failure(s)" % len(failures))
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
