#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Drives the program's own cutter in a private Xvfb: press "Salvar todos os cortes...", answer the folder dialog.
Usage: drive-cutter.py OUT_DIR   (the cut marks 1 s to 4 s were posted by CutterTaskProbe through the program's own events)"""
import subprocess, sys, time
from pathlib import Path

out = Path(sys.argv[1])


def sh(*a):
    return subprocess.run(list(a), capture_output=True, text=True).stdout


def shot(name):
    subprocess.run(['import', '-window', 'root', str(out / name)], capture_output=True)


def click(x, y):
    sh('xdotool', 'mousemove', str(x), str(y))
    time.sleep(0.4)
    sh('xdotool', 'click', '1')


def names():
    return sorted(set(l for l in sh('xdotool', 'search', '--name', '.', 'getwindowname', '%@').splitlines() if l.strip() and l not in ('FocusProxy', 'Content window')))


click(218, 142)          # Salvar todos os cortes...
time.sleep(3)
shot('cutter-save-dialog.png')
(out / 'cutter-save-dialog-windows.txt').write_text('\n'.join(names()) + '\n')
Path('/scratch/cuts').mkdir(exist_ok=True)
click(420, 308)          # the folder name field
sh('xdotool', 'key', 'ctrl+a')
sh('xdotool', 'type', '--delay', '20', '/scratch/cuts')
time.sleep(0.5)
shot('cutter-save-typed.png')
click(511, 382)          # Abrir
time.sleep(8)
shot('cutter-after-save.png')
(out / 'cutter-after-save-windows.txt').write_text('\n'.join(names()) + '\n')
