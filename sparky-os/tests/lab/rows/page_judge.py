#!/usr/bin/python3 -I
"""page_judge.py PAGE QMLLOG GRAPH: judges the Sound Quality page rows (rows/page_row.sh). PAGE holds the DUMP and RESULT lines the page rig's
harness printed for the page's own QML type (SoundFormats of plasma-pa); QMLLOG is qml6's raw output; GRAPH is `pw-metadata -n settings`
read by the row after the page's last change. What a holding page does, against the fixture's own table (the fake devices of the audio
rig: bench/rig/asound.conf and its ELD file; never against what the page printed):
  lists   every device with the rates and the formats the fixture declares: a DAC (44.1 to 192 kHz, 16/24/32 bit), a 48 kHz only device,
          a 16 bit only device, an HDMI sink (32 to 96 kHz; its ELD: LPCM 16/20/24 bit up to 96 kHz and AC-3 six channels) and a
          Bluetooth sink with its codec (aac, 44.1 and 48 kHz, 16 bit)
  chosen  a rate the person chooses for the graph (96 kHz, allowed 44.1, 48 and 96) is accepted ("in use") and reaches the running graph:
          the page's own reading says 96000 and so does PipeWire, read by the row (clock.rate and clock.allowed-rates)
  refused a rate a device cannot take (96 kHz on the 48 kHz only device) is refused with a sentence that says it was not kept and that
          the earlier settings stay, and the device keeps no choice of the person's
Exit 0 holds, 1 does not (a page that is not there: the QML type does not exist), 77 the session did not start, 2 a crash."""
import json
import os
import re
import sys
import traceback


def _crash(*a):
    traceback.print_exception(*a)
    os._exit(2)


sys.excepthook = _crash

page, qmllog, graph = sys.argv[1:4]
raw = open(qmllog, errors="replace").read() if os.path.exists(qmllog) else ""
lines = [l for l in open(page, errors="replace")] if os.path.exists(page) else []
if not lines:
    if re.search(r'SoundFormats is not a type|is not installed|module "org.kde.plasma.private.volume"', raw):
        first = [l for l in raw.splitlines() if "not a type" in l or "not installed" in l][0]
        print("the page is not there: the QML type SoundFormats of the Sound Quality page does not exist in this plasma-pa (%s)" % first.strip())
        sys.exit(1)
    print("SKIP: the page rig printed nothing and qml6 did not say why: %s" % " | ".join(raw.splitlines()[-3:]))
    sys.exit(77)
dumps, results = {}, []
for l in lines:
    k, _, j = l.partition(" ")
    d = json.loads(j)
    if k == "DUMP":
        dumps[d["name"]] = d
    else:
        results.append(d)
FIX = {  # name: (kind, rates, formats), from bench/rig/asound.conf
    "alsa_output.rig_dac": ("alsa", [44100, 48000, 88200, 96000, 176400, 192000], ["S16LE", "S24LE", "S32LE"]),
    "alsa_output.rig_only48": ("alsa", [48000], ["S16LE", "S32LE"]),
    "alsa_output.rig_pcm16": ("alsa", [44100, 48000], ["S16LE"]),
    "alsa_output.rig_hdmi": ("hdmi", [32000, 44100, 48000, 88200, 96000], ["S16LE", "S24LE", "S32LE"]),
    "bluez_output.rig_bt": ("bluetooth", [44100, 48000], ["S16LE"]),
}
ok = True


def say(good, text):
    global ok
    ok = ok and good
    print("%s: %s" % ("holds" if good else "does not hold", text))


start = dumps.get("0-start")
if not start:
    say(False, "the page printed no list of devices")
else:
    devs = {d["name"]: d for d in start["devices"]}
    for name, (kind, rates, formats) in FIX.items():
        d = devs.get(name)
        if not d:
            say(False, "%s is not listed" % name)
            continue
        say(sorted(d["rates"]) == rates and sorted(d["formats"]) == formats and d.get("kind") == kind,
            "%s lists %s Hz and %s (the fixture declares %s and %s)" % (name, d["rates"], d["formats"], rates, formats))
    hdmi = devs.get("alsa_output.rig_hdmi", {})
    eld = hdmi.get("eld") or []
    flat = json.dumps(eld)
    say(bool(eld) and "AC-3" in flat and all(str(r) in flat for r in (32000, 44100, 48000, 88200, 96000)) and all(str(b) in flat for b in (16, 20, 24)),
        "the HDMI sink shows its ELD: LPCM up to 96 kHz at 16, 20 and 24 bit, and AC-3 (%s)" % flat[:120])
    say(devs.get("bluez_output.rig_bt", {}).get("codec") == "aac", "the Bluetooth sink shows its codec (%s)" % devs.get("bluez_output.rig_bt", {}).get("codec"))
chosen = next((r for r in results if r["what"] == "graph"), None)
after = dumps.get("1-after-graph")
say(bool(chosen and chosen["ok"]) and bool(after) and after["graph"].get("rate") == 96000 and after["graph"].get("allowedRates") == [44100, 48000, 96000],
    "the chosen rate is accepted (%s) and the page reads the graph at %s Hz, allowed %s" % (
        chosen["message"].get("text") if chosen else "no answer", after["graph"].get("rate") if after else "?", after["graph"].get("allowedRates") if after else "?"))
g = open(graph, errors="replace").read() if os.path.exists(graph) else ""
rate = re.search(r"key:'clock\.rate' value:'(\d+)'", g)
allowed = re.search(r"key:'clock\.allowed-rates' value:'([^']*)'", g)
nums = sorted(int(x) for x in re.findall(r"\d+", allowed.group(1))) if allowed else []
say(bool(rate) and rate.group(1) == "96000" and nums == [44100, 48000, 96000], "PipeWire itself says clock.rate %s and clock.allowed-rates %s" % (rate.group(1) if rate else "?", nums))
refused = next((r for r in results if r["what"] == "device:alsa_output.rig_only48"), None)
text = (refused["message"].get("text") or "") if refused else ""
say(bool(refused) and refused["ok"] is False and "not kept" in text and "earlier settings stay" in text,
    "the rate the 48 kHz only device cannot take is refused and said: %r" % text)
post = dumps.get("2-after-refusal")
kept = post and "alsa_output.rig_only48" not in (post.get("user", {}).get("devices") or {})
say(bool(kept), "the refused choice is not kept in the person's settings")
sys.exit(0 if ok else 1)
