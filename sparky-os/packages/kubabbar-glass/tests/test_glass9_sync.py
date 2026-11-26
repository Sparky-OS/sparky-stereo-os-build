#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""test_glass9_sync.py BIN_DIR OUTPUT: kubabbar-glass-9-sync and kubabbar-glass-9-scrolling, case by case, each in a fresh
home, with the real kreadconfig6, kwriteconfig6 and problems engine; fc-list (Charcoal present or not) and dbus-send are
stubs. Run as an ordinary user in a container. Writes OUTPUT/results.json; exits 1 when a case fails."""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

BIN = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
DANIEL_LIKE = ("[General]\nfont=Charcoal,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\nmenuFont=Virtue,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n"
               "smallestReadableFont=Charcoal,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\nfixed=Terminus,10,-1,5,700,0,0,0,0,0,0,0,0,0,0,1\n"
               "[WM]\nactiveFont=Helvetica,9,-1,5,700,0,0,0,0,0,0,0,0,0,0,1\n")
results = []


def home(charcoal):
    h = Path(tempfile.mkdtemp(prefix="glass9-"))
    (h / ".config/kdedefaults").mkdir(parents=True)
    stubs = h / "stubs"
    stubs.mkdir()
    (stubs / "fc-list").write_text(f"#!/bin/sh\necho fc-list \"$@\" >> {h}/calls\nexit {0 if charcoal else 1}\n")
    (stubs / "dbus-send").write_text(f"#!/bin/sh\necho dbus-send \"$@\" >> {h}/calls\nexit 0\n")
    for s in stubs.iterdir():
        s.chmod(0o755)
    return h


def env(h):
    e = dict(os.environ, HOME=str(h), XDG_CONFIG_HOME=str(h / ".config"), XDG_STATE_HOME=str(h / ".local/state"),
             XDG_CONFIG_DIRS=f"{h}/.config/kdedefaults:/etc/xdg", LANG="C.UTF-8")
    e["PATH"] = f"{h}/stubs:{BIN}:{e['PATH']}"
    return e


def run(h, *argv):
    return subprocess.run(list(argv), env=env(h), capture_output=True, text=True)


def read(h, file, group, key):
    return subprocess.run(["kreadconfig6", "--file", file, "--group", group, "--key", key], env=env(h),
                          capture_output=True, text=True).stdout.strip()


def apply_look(h, look):
    (h / ".config/kdedefaults/package").write_text(look)
    if look == "kubabbar-glass-9":   # what Plasma's Look and Feel manager writes for the look's colours
        subprocess.run(["kwriteconfig6", "--file", f"{h}/.config/kdedefaults/kdeglobals", "--group", "General",
                        "--key", "ColorScheme", "kubabbar-glass-9"], env=env(h), check=True)


def check(name, ok, detail):
    results.append({"case": name, "pass": bool(ok), "detail": detail})


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest() if Path(p).exists() else None


# 1. another look applied: nothing is written
h = home(False)
apply_look(h, "org.kde.breeze.desktop")
r = run(h, "kubabbar-glass-9-sync")
check("another look: nothing written", r.returncode == 0 and not (h / ".config/kdedefaults/kdeglobals").exists()
      and not (h / ".config/kdedefaults/Kvantum").exists(), {"exit": r.returncode, "stderr": r.stderr[-300:]})

# 2. the look applied, Charcoal not installed, no fonts of the person's own
h = home(False)
apply_look(h, "kubabbar-glass-9")
r = run(h, "kubabbar-glass-9-sync")
dk = f"{h}/.config/kdedefaults/kdeglobals"
font = read(h, dk, "General", "font")
theme = read(h, f"{h}/.config/kdedefaults/Kvantum/kvantum.kvconfig", "General", "theme")
check("look applied, Charcoal missing: the bold free fallback and the lavender theme",
      r.returncode == 0 and font.startswith("Noto Sans Display,9,") and ",700," in font and theme == "KubabbarGlass9"
      and read(h, dk, "General", "fixed").startswith("Monaco,10,") and read(h, dk, "General", "smallestReadableFont").startswith("Geneva,8,")
      and read(h, dk, "WM", "activeFont") == font and (h / ".config/kdedefaults/kubabbar-glass-9-sync.written").exists()
      and "refreshFonts" in (h / "calls").read_text(),
      {"exit": r.returncode, "font": font, "theme": theme, "stderr": r.stderr[-300:]})
# the cascade a session sees: the person has no font of their own, so the look's is the value
check("cascade without own fonts gives the look's font", read(h, "kdeglobals", "General", "font") == font,
      {"cascaded": read(h, "kdeglobals", "General", "font")})

# 3. the person's own fonts (Daniel's kind of settings) stay untouched and win
h = home(False)
(h / ".config/kdeglobals").write_text(DANIEL_LIKE)
before = sha(h / ".config/kdeglobals")
apply_look(h, "kubabbar-glass-9")
r = run(h, "kubabbar-glass-9-sync")
check("own fonts: the person's kdeglobals byte for byte the same", r.returncode == 0 and sha(h / ".config/kdeglobals") == before,
      {"exit": r.returncode})
check("own fonts win in the cascade", read(h, "kdeglobals", "General", "menuFont").startswith("Virtue,9,")
      and read(h, "kdeglobals", "General", "font").startswith("Charcoal,9,"),
      {"menuFont": read(h, "kdeglobals", "General", "menuFont"), "font": read(h, "kdeglobals", "General", "font")})

# 4. Charcoal installed: the look names it, at its own (regular) weight
h = home(True)
apply_look(h, "kubabbar-glass-9")
r = run(h, "kubabbar-glass-9-sync")
font = read(h, f"{h}/.config/kdedefaults/kdeglobals", "General", "font")
check("Charcoal installed: named at its regular weight", r.returncode == 0 and font.startswith("Charcoal,9,") and ",400," in font,
      {"font": font})

# 5. the accent follows the person's scheme; the scroll arrows option picks the Apart theme
h = home(False)
apply_look(h, "kubabbar-glass-9")
subprocess.run(["kwriteconfig6", "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme", "kubabbar-glass-9-ivy"],
               env=env(h), check=True)
r = run(h, "kubabbar-glass-9-scrolling", "apart")
theme = read(h, f"{h}/.config/kdedefaults/Kvantum/kvantum.kvconfig", "General", "theme")
check("accent Ivy, arrows apart", r.returncode == 0 and theme == "KubabbarGlass9IvyApart"
      and read(h, "kubabbar-glass-9rc", "Scrolling", "Arrows") == "apart",
      {"exit": r.returncode, "theme": theme, "stdout": r.stdout[-200:], "stderr": r.stderr[-300:]})
r = run(h, "kubabbar-glass-9-scrolling", "together")
theme = read(h, f"{h}/.config/kdedefaults/Kvantum/kvantum.kvconfig", "General", "theme")
check("arrows together again", r.returncode == 0 and theme == "KubabbarGlass9Ivy", {"theme": theme})
r = run(h, "kubabbar-glass-9-scrolling", "sideways")
check("an unknown choice is refused and changes nothing", r.returncode == 2 and read(h, "kubabbar-glass-9rc", "Scrolling", "Arrows") == "together",
      {"exit": r.returncode, "stderr": r.stderr[-200:]})

# 6. another look applied afterwards: exactly what was written goes; a value changed since stays
h = home(False)
apply_look(h, "kubabbar-glass-9")
run(h, "kubabbar-glass-9-sync")
dk = f"{h}/.config/kdedefaults/kdeglobals"
subprocess.run(["kwriteconfig6", "--file", dk, "--group", "General", "--key", "fixed", "Hack,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"],
               env=env(h), check=True)
apply_look(h, "org.kde.breeze.desktop")
r = run(h, "kubabbar-glass-9-sync")
check("another look: the written keys removed, a changed one kept",
      r.returncode == 0 and read(h, dk, "General", "font") == "" and read(h, dk, "General", "fixed").startswith("Hack,")
      and read(h, f"{h}/.config/kdedefaults/Kvantum/kvantum.kvconfig", "General", "theme") == ""
      and not (h / ".config/kdedefaults/kubabbar-glass-9-sync.written").exists(),
      {"exit": r.returncode, "font": read(h, dk, "General", "font"), "fixed": read(h, dk, "General", "fixed")})

# 7. an unreadable input stops the run and is kept as the person's problem
h = home(False)
apply_look(h, "kubabbar-glass-9")
(h / ".config/kdeglobals").write_text(DANIEL_LIKE)
(h / ".config/kdeglobals").chmod(0)
r = run(h, "kubabbar-glass-9-sync")
listed = run(h, "sparky-stereo-problems", "list")
(h / ".config/kdeglobals").chmod(0o644)
check("an unreadable kdeglobals stops the run and is said", r.returncode == 1 and "kubabbar-glass-9" in listed.stdout
      and not (h / ".config/kdedefaults/kubabbar-glass-9-sync.written").exists(),
      {"exit": r.returncode, "list": listed.stdout[-300:]})

(OUT / "results.json").write_text(json.dumps(results, indent=1, ensure_ascii=False) + "\n")
for row in results:
    print("PASS" if row["pass"] else "FAIL", row["case"])
failed = sum(not row["pass"] for row in results)
print(f"{len(results) - failed} of {len(results)} cases pass")
sys.exit(1 if failed else 0)
