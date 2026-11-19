#!/usr/bin/python3 -I
"""audio_detect.py CASE: makes a fixture tree in the style of the kernel's /proc/asound for one sound device and asks the
engine (sparky-stereo-audio detect) what it found. The expectation is written here, from the fixture's own table and the
CTA-861 short audio descriptors in it, never from the engine.

  51          a 5.1 analog card (three stereo converters), 44.1 to 192 kHz, 16/24/32 bit
  16bit       a USB sound card whose only format is S16_LE
  hdmi        an HDMI sink whose ELD lists LPCM (32 44.1 48 96 kHz, 16 20 24 bit) and AC-3, E-AC-3, DTS, DTS-HD and TrueHD (MAT) with other
              rates: only the LPCM rates count for the graph, the encoded ones are for passthrough
  headphones  an analog codec with a headphone jack: the engine must name the port type
Exit 0 holds, 1 does not hold (stock Debian has no engine at all), 77 cannot run."""
import os
import sys
import traceback


def _crash(*a):
    traceback.print_exception(*a)
    os._exit(2)


sys.excepthook = _crash

import os
import re
import shutil
import subprocess
import sys
import tempfile

case = sys.argv[1]
engine = shutil.which("sparky-stereo-audio")
if not engine:
    print("no sparky-stereo-audio on this system: the stock sound system reads no device and makes no choice")
    sys.exit(1)
root = tempfile.mkdtemp(prefix="lab22-asound-", dir=os.environ.get("TMPDIR", "/tmp"))


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)


def codec(name, nodes, default=("44100 48000 88200 96000 176400 192000", "16 20 24 32"), pins=""):
    t = ["Codec: %s" % name, "Address: 0", "Default PCM:", "    rates [0x7f0]: %s" % default[0],
         "    bits [0xe]: %s" % default[1], "    formats [0x1]: PCM"]
    for nid, dev, typ in nodes:
        t += ["Node 0x%02x [Audio Output] wcaps 0x41: Stereo" % nid]
        if dev:
            t += ['  Device: name="%s", type="%s", device=0' % (dev, typ)]
    t += [pins]
    return "\n".join(t) + "\n"


if case == "51":
    w(root + "/card0/id", "Rig51\n")
    w(root + "/card0/codec#0", codec("Rig 5.1 Card", [(2, "Rig 5.1 Analog", "Audio"), (3, None, None), (4, None, None)]))
    want = {"name": "Rig 5.1 Analog", "rates": [44100, 48000, 88200, 96000, 176400, 192000], "bits": 32}
elif case == "16bit":
    w(root + "/card0/id", "RigUSB16\n")
    w(root + "/card0/stream0", "Rig USB16 at usb-0000:00:1d.0-1, full speed : USB Audio\n\nPlayback:\n  Status: Stop\n  Interface 1\n"
      "    Altset 1\n    Format: S16_LE\n    Channels: 2\n    Endpoint: 0x01 (1 OUT) (ASYNC)\n    Rates: 44100, 48000\n")
    want = {"name": "RigUSB16", "rates": [44100, 48000], "bits": 16, "only": True}
elif case == "hdmi":
    w(root + "/card0/id", "RigHDMIAVR\n")
    w(root + "/card0/codec#0", codec("Rig HDMI AVR", [(2, None, None), (4, "HDMI 0", "HDMI")], default=("32000 44100 48000 88200 96000 176400 192000", "16 20 24")))
    eld = ["monitor_present\t\t1", "eld_valid\t\t1", "monitor_name\t\tRIG AVR", "connection_type\t\tHDMI", "sad_count\t\t6",
           "sad0_coding_type\t[0x1] LPCM", "sad0_channels\t\t8", "sad0_rates\t\t[0x1e0] 32000 44100 48000 96000", "sad0_bits\t\t[0xe] 16 20 24",
           "sad1_coding_type\t[0x2] AC-3", "sad1_channels\t\t6", "sad1_rates\t\t[0xe0] 32000 44100 48000",
           "sad2_coding_type\t[0xa] E-AC-3/DD+ (Dolby Digital Plus)", "sad2_channels\t\t8", "sad2_rates\t\t[0x60] 44100 48000",
           "sad3_coding_type\t[0x7] DTS", "sad3_channels\t\t6", "sad3_rates\t\t[0x2e0] 44100 48000 88200 192000",
           "sad4_coding_type\t[0xb] DTS-HD", "sad4_channels\t\t8", "sad4_rates\t\t[0x6e0] 44100 48000 88200 96000 192000",
           "sad5_coding_type\t[0xc] MAT (MLP, Dolby TrueHD)", "sad5_channels\t\t8", "sad5_rates\t\t[0x680] 48000 96000 176400 192000"]
    w(root + "/card0/eld#0.0", "\n".join(eld) + "\n")
    want = {"name": "RIG AVR", "rates": [32000, 44100, 48000, 96000], "bits": 24, "absent": [88200, 176400, 192000]}
elif case == "headphones":
    w(root + "/card0/id", "RigHP\n")
    pins = ("Node 0x14 [Pin Complex] wcaps 0x40058d: Stereo Amp-Out\n  Pincap 0x00010014: OUT EAPD Detect\n"
            "  Pin Default 0x0421101f: [Jack] HP Out at Ext Front\n    Conn = 1/8, Color = Green\n")
    w(root + "/card0/codec#0", codec("Rig Analog", [(2, "Rig Analog", "Audio")], pins=pins))
    want = {"name": "Rig Analog", "rates": [44100, 48000, 88200, 96000, 176400, 192000], "bits": 32, "port": "headphone"}
else:
    print("unknown case", case)
    sys.exit(77)
env = dict(os.environ, SPARKY_STEREO_AUDIO_PROC=root, SPARKY_STEREO_AUDIO_CPU_COST="5", LANGUAGE="en", LANG="C")
p = subprocess.run([engine, "detect"], capture_output=True, text=True, env=env)
print(p.stdout)
shutil.rmtree(root, ignore_errors=True)
if p.returncode != 0:
    print("detect exit", p.returncode, p.stderr[-300:])
    sys.exit(1)
line = next((l for l in p.stdout.splitlines() if want["name"] in l and "Hz" in l), None)
if line is None:
    print("the engine did not list %r" % want["name"])
    sys.exit(1)
rates = [int(x) for x in re.findall(r"\b\d{5,6}\b", line.split(":", 1)[1])]
ok = rates == want["rates"]
print("expected rates %s, engine %s: %s" % (want["rates"], rates, "equal" if ok else "DIFFERENT"))
bitm = re.search(r"(?:up to (\d+) bit|(\d+) bit only)", line)
bits = int(bitm.group(1) or bitm.group(2)) if bitm else None
print("expected %d bit%s, engine %s" % (want["bits"], " only" if want.get("only") else "", bits))
ok = ok and bits == want["bits"] and (not want.get("only") or "only" in line)
for r in want.get("absent", []):
    if r in rates:
        print("the engine listed %d Hz, a rate only an encoded format (passthrough) has" % r)
        ok = False
if want.get("port"):
    has = want["port"] in p.stdout.lower()
    print("port type %r named in the engine's answer: %s" % (want["port"], has))
    ok = ok and has
sys.exit(0 if ok else 1)
