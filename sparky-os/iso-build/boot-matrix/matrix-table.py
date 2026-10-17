#!/usr/bin/env python3
"""matrix-table.py : print the boot-matrix results as Markdown tables, from the run folders.

Every run folder is classified by classify.py's rules (desktop = the Plasma Welcome window is on the screen).
A cell is "pass Ns" (first desktop frame at N seconds), or "fail: <reason>" with the reason read from the
serial log (firmware and GRUB text) or the last frame ("black screen", "stuck at menu", "boot manager").
"""
import json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
spec = importlib.util.spec_from_file_location("classify", os.path.join(os.path.dirname(os.path.abspath(__file__)), "classify.py"))
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "classify.py")).read().replace("\nmain()\n", "\n")
ns = {}
exec(compile(src, "classify.py", "exec"), ns)
label, tkey = ns["label"], ns["tkey"]

CASES = ["seabios", "ovmf", "sb", "sb-sbat2024", "sb-2011only", "sb-2023only", "ia32"]
KNOWN = [("SBAT self-check failed", "shim: SBAT self-check failed, power off"),
         ("Verifying shim SBAT data failed", "shim: SBAT verification failed"),
         ("Security Policy Violation", "Security Policy Violation"),
         ("bad shim loader signature", "GRUB: bad shim loader signature")]

def run(d):
    frames = sorted([f[:-4] for f in os.listdir(d) if f.endswith(".png") and f != "sheet.png"], key=tkey)
    times = {}
    try:
        for s in json.load(open(os.path.join(d, "result.json"))).get("steps", []):
            if "shot" in s:
                times[s["shot"]] = s["t"]
    except Exception:
        return None
    labs = [(f, label(os.path.join(d, f + ".png"))) for f in frames]
    for f, l in labs:
        if l == "desktop":
            return ("pass", times.get(f), "")
    serial = ""
    try:
        serial = open(os.path.join(d, "serial.log"), errors="replace").read()
    except Exception:
        pass
    for key, text in KNOWN:
        if key in serial:
            return ("fail", None, text)
    last = labs[-1][1] if labs else "-"
    seen = [l for _, l in labs]
    why = {"black": "black screen after the menu" if "menu" in seen else "black screen",
           "menu": "stuck at the boot menu (GRUB still loading, or hung)", "text": "firmware boot manager (no boot)",
           "splash": "still at the splash when the timeline ended", "garbled": "garbled picture"}.get(last, last)
    if last == "black" and "splash" in seen:
        why = "slow: the splash was up, no desktop yet when the timeline ended"
    return ("fail", None, why)

def cell(paths):
    """paths: run folders for this cell, later ones override earlier ones (a rerun with a longer timeline)"""
    r = None
    for path in paths:
        if os.path.isdir(path):
            r = run(path) or r
    if r is None:
        return "-"
    return ("pass %ds" % round(r[1])) if r[0] == "pass" else "fail: " + r[2]

def table(title, base, cases=CASES):
    print("\n**%s**\n" % title)
    print("| firmware | CD (El Torito) | USB disk (dd) |")
    print("|---|---|---|")
    bases = base.split("+")
    for c in cases:
        print("| %s | %s | %s |" % (c, cell([os.path.join(b, c + "-cd") for b in bases]), cell([os.path.join(b, c + "-usb") for b in bases])))

if __name__ == "__main__":
    # arguments: "title=dir[+dir2][#case,case,...]" ; later dirs override earlier ones, the case list limits the rows
    for arg in sys.argv[1:]:
        title, base = arg.split("=", 1)
        cases = CASES
        if "#" in base:
            base, cl = base.split("#", 1)
            cases = cl.split(",")
        table(title, base, cases)
