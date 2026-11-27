#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""The Overview presets' tests (queue row 182): for each fixture computer the preset chosen, every card on the "every
GPU" presets, each card's reported sensors on the page and no sensor its driver does not report, the not-reported note
in the ten languages; then the login flow on a person's folders: the first choice once, the fast path, a hardware
change that composes again only the presets the person did not edit or remove, a person who had arranged their pages,
and a probe that fails. Runs in a container with kreadconfig6, kwriteconfig6 and sparky-stereo-problems.
  compose.py PROGRAM DATA_DIR"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from machines import build  # noqa: E402

PROGRAM, DATA = sys.argv[1], sys.argv[2]
LANGS = ["en", "pl", "pt_BR", "fr", "de", "es", "ja", "ko", "zh_CN", "zh_TW"]
FAILED = []
PASSED = 0


def check(condition, what):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILED.append(what)
        print("FAIL", what)


def run(env, *args, home=None):
    e = {k: v for k, v in os.environ.items() if not k.startswith("SPARKY_STEREO_")}
    e.update(env)
    e["SPARKY_STEREO_SYSTEMMONITOR_DATA"] = DATA
    if home:
        e.update({"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"), "XDG_DATA_HOME": str(home / ".local/share"),
                  "XDG_STATE_HOME": str(home / ".local/state"), "XDG_CONFIG_DIRS": str(home / "etc-xdg")})
    return subprocess.run([sys.executable, "-I", PROGRAM, *args], capture_output=True, text=True, env=e)


def parse(text):
    """A KConfig file as {group path: {key: value}}; the group path is the bracketed names joined by "/"."""
    groups, current = {}, None
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        if line.startswith("["):
            current = "/".join(re.findall(r"\[([^\]]*)\]", line))
            groups.setdefault(current, {})
        else:
            key, _, value = line.partition("=")
            groups[current][key] = value
    return groups


def sensors(groups):
    out = []
    for name, keys in groups.items():
        if name.endswith("/Sensors"):
            for key in ("highPrioritySensorIds", "totalSensors"):
                if key in keys:
                    out += json.loads(keys[key].replace("\\\\", "\\"))
    return out


def face_titles(groups, lang="en"):
    key = "Title" if lang == "en" else "Title[%s]" % lang
    return [keys[key] for name, keys in groups.items() if name.endswith("/Appearance") and key in keys]


def strings(lang):
    table = {}
    for line in Path(DATA, "lang", lang).read_text(encoding="utf-8").splitlines():
        m = re.fullmatch(r'(LOCAL[0-9]+)="([^"]*)"', line)
        if m:
            table[m.group(1)] = m.group(2)
    return table


EXPECT = {
    # machine: (preset, [(card, vendor, reported ids)], desktop card index or None)
    "station": ("every-gpu-many", [(0, "nvidia", ["usage", "usedVram", "totalVram", "temperature", "power"]),
                                   (1, "amd", ["usage", "usedVram", "totalVram", "temperature", "power1"])], 1),
    "a10": ("every-gpu-few", [(0, "amd", ["usage", "usedVram", "totalVram", "temperature"]),
                              (1, "amd", ["usedVram", "totalVram", "temperature"])], 0),
    "one-amd": ("one-gpu-many", [(0, "amd", ["usage", "usedVram", "totalVram", "temperature", "power1"])], 0),
    "intel-i915": ("one-gpu-few", [(0, "intel", [])], 0),
    "intel-i915-perf": ("one-gpu-few", [(0, "intel", ["usage"])], 0),
    "intel-xe": ("one-gpu-many", [(0, "intel", [])], 0),
    # the NVIDIA card under the root port 00:01.0 comes before the Intel card at 00:02.0 in udev's order
    "laptop-intel-nvidia": ("every-gpu-many", [(0, "nvidia", ["usage", "usedVram", "totalVram", "temperature"]),
                                               (1, "intel", [])], 1),
    "nouveau": ("one-gpu-few", [(0, "nvidia", [])], 0),
    "nvidia-no-smi": ("one-gpu-few", [(0, "nvidia", [])], 0),
    "virtio": ("one-gpu-few", [], None),
    "server-bmc": ("one-gpu-many", [(0, "amd", ["usage", "usedVram", "totalVram", "temperature", "power1"])], 0),
    "five-amd": ("every-gpu-many", [(i, "amd", ["usage", "usedVram", "totalVram", "temperature", "power1"])
                                    for i in range(5)], 0),
}
ALL = {"usage": ["usage"], "memory": ["usedVram", "totalVram"], "temperature": ["temperature"],
       "power": ["power", "power1"]}
WORD = {"usage": "LOCAL9", "memory": "LOCAL10", "temperature": "LOCAL11", "power": "LOCAL12"}

for machine, (preset, cards, desktop) in EXPECT.items():
    root = Path(tempfile.mkdtemp(prefix="sm182-%s-" % machine))
    env = build(machine, root)
    explain = run(env, "--explain")
    check(explain.returncode == 0, "%s: --explain exit %d %s" % (machine, explain.returncode, explain.stderr))
    check("preset sparky-overview-%s-threads.page" % preset in explain.stdout,
          "%s: chose %s, wanted %s" % (machine, explain.stdout.splitlines()[-1:], preset))
    for gpus_kind in ("one", "every"):
        for threads_kind in ("few", "many"):
            target = root / ("%s-%s.page" % (gpus_kind, threads_kind))
            r = run(env, "--compose", gpus_kind, threads_kind, str(target))
            check(r.returncode == 0, "%s %s-%s: compose exit %d %s" % (machine, gpus_kind, threads_kind, r.returncode,
                                                                     r.stderr[-300:]))
            groups = parse(target.read_text(encoding="utf-8"))
            ids = sensors(groups)
            shown = cards if gpus_kind == "every" else [c for c in cards if c[0] == desktop]
            for index, vendor, reported in cards:
                prefix = "gpu/gpu%d/" % index
                on_page = sorted(i[len(prefix):] for i in ids if i.startswith(prefix))
                if (index, vendor, reported) in shown:
                    check(on_page == sorted(["name"] + reported), "%s %s-%s gpu%d: page has %s, wanted %s" % (
                        machine, gpus_kind, threads_kind, index, on_page, sorted(["name"] + reported)))
                    missing = [s for s, sub in ALL.items() if not any(x in reported for x in sub)]
                    for lang in LANGS:
                        t = strings(lang)
                        titles = face_titles(groups, lang)
                        if missing:
                            note = t["LOCAL8"] % t["LOCAL13"].join(t[WORD[s]] for s in missing)
                            check(note in titles, "%s %s-%s gpu%d %s: no note %r" % (
                                machine, gpus_kind, threads_kind, index, lang, note))
                else:
                    check(on_page == [], "%s %s-%s: gpu%d on a one-GPU page" % (machine, gpus_kind, threads_kind, index))
            # every face and the page carry the ten languages
            for name, keys in groups.items():
                if name.endswith("/Appearance") or name == "page":
                    for lang in LANGS[1:]:
                        check("Title[%s]" % lang in keys, "%s: %s lacks Title[%s]" % (machine, name, lang))
            check(any(i == "cpu/cpu\\d+/usage" for i in ids), "%s: no per-thread sensor" % machine)
            check(any(k.get("chartFace") == ("org.kde.ksysguard.facegrid" if threads_kind == "many"
                                             else "org.kde.ksysguard.linechart") and "cpu/cpu" in json.dumps(
                groups.get(n[:-len("/Appearance")] + "/Sensors", {}))
                for n, k in groups.items() if n.endswith("/Appearance")), "%s: thread face kind" % machine)
            if not cards:
                check(strings("en")["LOCAL14"] in face_titles(groups), "%s: no zero-card note" % machine)
            if gpus_kind == "every" and machine in ("virtio", "server-bmc"):
                check(any("Not measured by System Monitor" in t for t in face_titles(groups)),
                      "%s: the card ksystemstats does not measure is not named" % machine)
            if gpus_kind == "every" and machine == "five-amd":
                rows = [n for n in groups if re.fullmatch(r"page/row-\d+/column-\d+", n)]
                gpu_rows = {}
                for n in rows:
                    sec = groups.get(n + "/section-0", {}).get("face", "")
                    hp = groups.get(sec + "/Sensors", {}).get("highPrioritySensorIds", "")
                    if "gpu/gpu" in hp:
                        gpu_rows.setdefault(n.split("/")[1], []).append(n)
                check(sorted(len(v) for v in gpu_rows.values()) == [1, 4], "five-amd: GPU rows %s" % gpu_rows)
    shutil.rmtree(root)

# The login flow on a person's folders
root = Path(tempfile.mkdtemp(prefix="sm182-login-"))
env = build("a10", root / "m")
calls = root / "smi-calls"
home = root / "home"
(home / "etc-xdg").mkdir(parents=True)
r = run(env, "--login", home=home)
check(r.returncode == 0, "login: exit %d %s" % (r.returncode, r.stderr))
pages = home / ".local/share/plasma-systemmonitor"
names = sorted(p.name for p in pages.glob("*.page"))
check(len(names) == 4, "login: pages %s" % names)


def kread(key, h=home):
    e = dict(os.environ, XDG_CONFIG_HOME=str(h / ".config"), XDG_CONFIG_DIRS=str(h / "etc-xdg"))
    return subprocess.run(["kreadconfig6", "--file", "systemmonitorrc", "--group", "General", "--key", key],
                          capture_output=True, text=True, env=e).stdout.strip()


check(kread("startPage") == "sparky-overview-every-gpu-few-threads.page", "login: start page %r" % kread("startPage"))
check(kread("hiddenPages").split(",")[0] == "overview.page" and len(kread("hiddenPages").split(",")) == 4,
      "login: hidden %r" % kread("hiddenPages"))
check(kread("pageOrder").startswith("sparky-overview-every-gpu-few-threads.page,overview.page,applications.page"),
      "login: order %r" % kread("pageOrder"))
before = {p.name: p.read_bytes() for p in pages.glob("*.page")}
rc_before = (home / ".config/systemmonitorrc").read_bytes()
# the fast path: an unchanged computer runs no nvidia-smi and writes nothing
env2 = dict(env)
env2["SPARKY_STEREO_NVIDIA_SMI"] = str(root / "smi-marker")
(root / "smi-marker").write_text("#!/bin/sh\ntouch %s\nexit 1\n" % calls)
(root / "smi-marker").chmod(0o755)
r = run(env2, "--login", home=home)
check(r.returncode == 0 and not calls.exists(), "fast path: exit %d, nvidia-smi called %s" % (r.returncode, calls.exists()))
check({p.name: p.read_bytes() for p in pages.glob("*.page")} == before, "fast path: pages changed")
# the person switches to KDE's Overview (as System Monitor's Edit Pages writes it), edits one preset, removes another
subprocess.run(["kwriteconfig6", "--file", str(home / ".config/systemmonitorrc"), "--group", "General", "--key",
                "startPage", "overview.page"], check=True)
edited = pages / "sparky-overview-every-gpu-few-threads.page"
edited.write_bytes(edited.read_bytes() + b"\n[page][row-9]\nname=row-9\n")
edited_bytes = edited.read_bytes()
(pages / "sparky-overview-one-gpu-many-threads.page").unlink()
rc_switched = (home / ".config/systemmonitorrc").read_bytes()
# the hardware changes: more threads
shutil.rmtree(root / "m")
from machines import MACHINES  # noqa: E402
MACHINES["a10"]["threads"] = 12
env = build("a10", root / "m")
r = run(env, "--login", home=home)
check(r.returncode == 0, "change: exit %d %s" % (r.returncode, r.stderr))
check(edited.read_bytes() == edited_bytes, "change: the person's edited preset was rewritten")
check(not (pages / "sparky-overview-one-gpu-many-threads.page").exists(), "change: a removed preset came back")
again = pages / "sparky-overview-every-gpu-many-threads.page"
check(again.read_bytes() != before[again.name] and b"columnCount=6" in again.read_bytes(),
      "change: an unedited preset was not composed again")
check((home / ".config/systemmonitorrc").read_bytes() == rc_switched, "change: the person's choice was written again")
check(kread("startPage") == "overview.page", "change: start page %r" % kread("startPage"))
MACHINES["a10"]["threads"] = 4
env = build("a10", root / "m4")
# a person who had arranged their pages
home2 = root / "home2"
(home2 / "etc-xdg").mkdir(parents=True)
(home2 / ".config").mkdir(parents=True)
(home2 / ".config/systemmonitorrc").write_text("[General]\nhiddenPages=history.page\nstartPage=processes.page\n")
r = run(env, "--login", home=home2)
check(r.returncode == 0, "arranged: exit %d" % r.returncode)
check(kread("startPage", home2) == "processes.page", "arranged: start page %r" % kread("startPage", home2))
hidden = kread("hiddenPages", home2).split(",")
check(hidden[0] == "history.page" and len(hidden) == 4 and "sparky-overview-every-gpu-few-threads.page" not in hidden,
      "arranged: hidden %r" % hidden)
# a person who edited KDE's Overview keeps it in view
home3 = root / "home3"
(home3 / "etc-xdg").mkdir(parents=True)
(home3 / ".local/share/plasma-systemmonitor").mkdir(parents=True)
(home3 / ".local/share/plasma-systemmonitor/overview.page").write_text("[page]\nTitle=Mine\n")
r = run(env, "--login", home=home3)
check(r.returncode == 0 and kread("startPage", home3) == "" and "overview.page" not in kread("hiddenPages", home3),
      "own overview: start %r hidden %r" % (kread("startPage", home3), kread("hiddenPages", home3)))
# an administrator's choice in /etc/xdg is kept as the person's would be
home4 = root / "home4"
(home4 / "etc-xdg").mkdir(parents=True)
(home4 / "etc-xdg/systemmonitorrc").write_text("[General]\nstartPage=processes.page\n")
r = run(env, "--login", home=home4)
check(r.returncode == 0 and kread("startPage", home4) == "processes.page", "administrator: start %r" % kread("startPage", home4))
# a probe that cannot read the computer: KDE's Overview stays, the person is told through the engine, then it clears
home5 = root / "home5"
(home5 / "etc-xdg").mkdir(parents=True)
broken = build("no-pci", root / "broken")
r = run(broken, "--login", home=home5)
check(r.returncode == 1 and not list((home5 / ".local/share/plasma-systemmonitor").glob("*.page")) and
      not (home5 / ".config/systemmonitorrc").exists(), "failure: exit %d, files written" % r.returncode)
e = dict(os.environ, XDG_STATE_HOME=str(home5 / ".local/state"), HOME=str(home5))
listed = subprocess.run(["sparky-stereo-problems", "list", "--json"], capture_output=True, text=True, env=e).stdout
check("overview-probe" in listed, "failure: no problem kept: %s" % listed[:300])
r = run(env, "--login", home=home5)
listed = subprocess.run(["sparky-stereo-problems", "list", "--json"], capture_output=True, text=True, env=e).stdout
check(r.returncode == 0 and "overview-probe" not in listed, "failure: not cleared after a probe that works: %s" % listed[:300])
shutil.rmtree(root)
print("%d passed, %d failed" % (PASSED, len(FAILED)))
sys.exit(1 if FAILED else 0)
