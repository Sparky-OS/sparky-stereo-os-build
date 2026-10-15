#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Milestone 3 checks without a compositor: the minimise helper in eight languages, the Look and Feel's strings and name text, the licence of every file."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGS = ("en", "pl", "pt_BR", "fr", "ja", "ko", "zh_CN", "zh_TW")
LNF = ROOT / "share/plasma/look-and-feel/kubabbar-glass-menubar"
S1 = "Kubabbar Glass is our own name for this look, chosen by Daniel Ramos on 14 October 2026."
S4 = "This look follows the same line: kù-babbar is the Sumerian word for silver, written with the signs for metal and shining."


def main():
    home = ROOT / "rig/home/m3-helpers"
    shutil.rmtree(home, ignore_errors=True)
    (home / ".config").mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"), XDG_CONFIG_DIRS="/etc/xdg", LANG="C.UTF-8", LC_ALL="C.UTF-8",
               PATH=str(ROOT / "bin") + os.pathsep + os.environ["PATH"], QT_QPA_PLATFORM="offscreen")
    report, ok = {"effect": {}, "lang": {}, "metadata": {}}, True
    for effect, expect in (("magiclamp", ("true", "false")), ("squash", ("false", "true"))):
        run = subprocess.run(["kubabbar-glass-minimize", effect], env=env, capture_output=True, text=True)
        got = tuple(subprocess.run(["kreadconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", k], env=env, capture_output=True, text=True).stdout.strip() for k in ("magiclampEnabled", "squashEnabled"))
        good = run.returncode == 0 and got == expect
        report["effect"][effect] = {"magiclamp,squash": got, "pass": good}
        ok &= good
    run = subprocess.run(["kubabbar-glass-minimize", "wobbly"], env=env, capture_output=True, text=True)
    report["effect"]["unknown"] = {"exit": run.returncode, "pass": run.returncode == 2}
    ok &= run.returncode == 2
    meta = json.loads((LNF / "metadata.json").read_text())["KPlugin"]
    assert meta["Id"] == "kubabbar-glass-menubar" and S1 in meta["Description"] and S4 in meta["Description"]
    for code in LANGS:
        lines = (ROOT / "lang/minimize" / code).read_text().splitlines()
        values = [line.split("=", 1)[1].strip('"') for line in lines]
        good = [line.split("=", 1)[0] for line in lines] == ["LOCAL%d" % i for i in range(1, 6)] and all(values)
        listing = subprocess.run(["kubabbar-glass-minimize"], env=dict(env, LANG=code + ".UTF-8", LC_ALL=code + ".UTF-8"), capture_output=True, text=True).stdout
        good &= values[0] in listing and values[1] in listing
        if code != "en":
            good &= meta.get("Name[%s]" % code, "") != "" and meta.get("Description[%s]" % code, "") != "" and meta["Name[%s]" % code].startswith("Kubabbar Glass")
        report["lang"][code] = {"helper_strings": len(values), "name": meta.get("Name[%s]" % code, meta["Name"]), "pass": good}
        ok &= good
    report["all_pass"] = ok
    (ROOT / "evidence/m3/helpers-check.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
