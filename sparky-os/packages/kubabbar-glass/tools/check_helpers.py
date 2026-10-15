#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Run the two helper scripts against a scratch home and read back what they wrote."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGS = ("en", "pl", "pt_BR", "fr", "ja", "ko", "zh_CN", "zh_TW")


def environment(home, **extra):
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"), LANG="C.UTF-8", LC_ALL="C.UTF-8", QT_QPA_PLATFORM="offscreen",
               PATH=str(ROOT / "bin") + os.pathsep + os.environ["PATH"])
    env.update(extra)
    return env


def read(env, file, group, key):
    return subprocess.run(["kreadconfig6", "--file", file, "--group", group, "--key", key], env=env, capture_output=True, text=True).stdout.strip()


def main():
    home = ROOT / "rig/home/helpers"
    shutil.rmtree(home, ignore_errors=True)
    (home / ".config").mkdir(parents=True)
    report, ok = {"style": {}, "gtk": {}, "lang": {}}, True
    for style, value in (("breeze", "Breeze"), ("fusion", "Fusion"), ("kvantum", "kvantum"), ("oxygen", "Oxygen")):
        env = environment(home, XDG_CONFIG_DIRS="/etc/xdg")
        run = subprocess.run(["kubabbar-glass-style", style], env=env, capture_output=True, text=True)
        got = read(env, "kdeglobals", "KDE", "widgetStyle")
        kv = read(env, str(home / ".config/Kvantum/kvantum.kvconfig"), "General", "theme") if style == "kvantum" else ""
        good = run.returncode == 0 and got == value and (style != "kvantum" or kv == "KubabbarGlass")
        ok &= good
        report["style"][style] = {"widgetStyle": got, "kvantum_theme": kv, "pass": good}
    run = subprocess.run(["kubabbar-glass-style", "gtk"], env=environment(home), capture_output=True, text=True)
    report["style"]["unknown"] = {"exit": run.returncode, "pass": run.returncode == 2}
    ok &= run.returncode == 2
    schemes = {"kubabbar-glass": ("Kubabbar-Glass", "false"), "OxygenDark": ("Sparky-Stereo-Oxygen", "true"), "BreezeDark": ("Breeze-Dark", "true"),
               "BreezeLight": ("Breeze", "false")}
    for scheme, (theme, dark) in schemes.items():
        env = environment(home, XDG_CONFIG_DIRS="/etc/xdg")
        subprocess.run(["kwriteconfig6", "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme", scheme], env=env, check=True)
        subprocess.run(["sparky-stereo-gtk-sync"], env=env, capture_output=True, check=True)
        values = {}
        for version in ("3.0", "4.0"):
            ini = str(home / ".config" / ("gtk-" + version) / "settings.ini")
            values[version] = (read(env, ini, "Settings", "gtk-theme-name"), read(env, ini, "Settings", "gtk-application-prefer-dark-theme"))
        good = all(v == (theme, dark) for v in values.values())
        ok &= good
        report["gtk"][scheme] = {"expected": [theme, dark], "gtk3": values["3.0"], "gtk4": values["4.0"], "pass": good}
    for code in LANGS:
        text = (ROOT / "lang" / code).read_text()
        keys = [line.split("=", 1)[0] for line in text.splitlines()]
        values = [line.split("=", 1)[1].strip('"') for line in text.splitlines()]
        good = keys == ["LOCAL%d" % i for i in range(1, 8)] and all(values)
        env = environment(home, LANG=code + ".UTF-8", LC_ALL=code + ".UTF-8")
        listing = subprocess.run(["kubabbar-glass-style"], env=env, capture_output=True, text=True).stdout
        good &= values[0] in listing and values[1] in listing
        ok &= good
        report["lang"][code] = {"strings": len(values), "listing_uses_language": values[0] in listing, "pass": good}
    report["all_pass"] = ok
    (ROOT / "evidence/m2/helpers-check.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
