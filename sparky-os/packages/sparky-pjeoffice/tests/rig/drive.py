#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Answers the program's own dialogs in a private Xvfb for the proofs: types the generated PIN into "Informe a senha" and presses Return,
presses Return on a window named by --accept. Takes a picture of every dialog it answers (--shots DIR). It never answers for a real
identity: the PIN is read from the fixture's generated file. Usage: drive.py PIN_FILE [--accept TITLE]... [--click TITLE:FX:FY]... [--shots DIR] [--seconds N]"""
import subprocess, sys, time
from pathlib import Path

pin = Path(sys.argv[1]).read_text().strip()
accept = [sys.argv[i + 1] for i, a in enumerate(sys.argv) if a == '--accept']
clicks = [sys.argv[i + 1].rsplit(':', 2) for i, a in enumerate(sys.argv) if a == '--click']   # TITLE:FRACTION_X:FRACTION_Y
shots = Path(sys.argv[sys.argv.index('--shots') + 1]) if '--shots' in sys.argv else None
seconds = int(sys.argv[sys.argv.index('--seconds') + 1]) if '--seconds' in sys.argv else 120
done = set()
seen = None
end = time.monotonic() + seconds


def geometry(wid):
    out = subprocess.run(['xdotool', 'getwindowgeometry', '--shell', wid], capture_output=True, text=True).stdout
    return {k: int(v) for k, v in (line.split('=') for line in out.split() if '=' in line)}


def click_field(wid):
    """Java's dialog has no window manager here: put the pointer in the password field (60 % down the dialog), click, and type."""
    g = geometry(wid)
    subprocess.run(['xdotool', 'mousemove', str(g['X'] + g['WIDTH'] // 2), str(g['Y'] + int(g['HEIGHT'] * 0.62))], capture_output=True)
    time.sleep(0.3)
    subprocess.run(['xdotool', 'click', '1'], capture_output=True)
    time.sleep(0.3)


def windows(name):
    out = subprocess.run(['xdotool', 'search', '--name', name], capture_output=True, text=True).stdout.split()
    return out


def watch():
    """A new set of window names is written down with a picture, so a dialog nobody taught this driver is found."""
    global seen
    out = subprocess.run(['xdotool', 'search', '--name', '.', 'getwindowname', '%@'], capture_output=True, text=True).stdout
    names = sorted(set(l for l in out.splitlines() if l.strip() and l not in ('FocusProxy', 'Content window')))
    if names != seen and shots:
        seen = names
        stamp = int(time.monotonic())
        (shots / ('windows-%d.txt' % stamp)).write_text('\n'.join(names) + '\n')
        subprocess.run(['import', '-window', 'root', str(shots / ('windows-%d.png' % stamp))], capture_output=True)


while time.monotonic() < end:
    watch()
    for wid in windows('Informe a senha'):
        if ('pin', wid) in done:
            continue
        time.sleep(1.5)
        if shots:
            subprocess.run(['import', '-window', 'root', str(shots / ('pin-%s.png' % wid))], capture_output=True)
        click_field(wid)
        subprocess.run(['xdotool', 'type', '--delay', '30', pin], capture_output=True)
        time.sleep(0.5)
        if shots:
            subprocess.run(['import', '-window', 'root', str(shots / ('pin-typed-%s.png' % wid))], capture_output=True)
        subprocess.run(['xdotool', 'key', 'Return'], capture_output=True)
        done.add(('pin', wid))
        print('answered the PIN dialog', wid, flush=True)
    for title, fx, fy in clicks:
        for wid in windows(title):
            if (title, wid) in done:
                continue
            time.sleep(1.5)
            g = geometry(wid)
            subprocess.run(['xdotool', 'mousemove', str(g['X'] + int(g['WIDTH'] * float(fx))), str(g['Y'] + int(g['HEIGHT'] * float(fy)))], capture_output=True)
            time.sleep(0.3)
            if shots:
                subprocess.run(['import', '-window', 'root', str(shots / ('click-%s-%s.png' % (title.replace(' ', '_'), wid)))], capture_output=True)
            subprocess.run(['xdotool', 'click', '1'], capture_output=True)
            done.add((title, wid))
            print('clicked', title, wid, flush=True)
    for title in accept:
        for wid in windows(title):
            if (title, wid) in done:
                continue
            time.sleep(1.5)
            if shots:
                subprocess.run(['import', '-window', 'root', str(shots / ('accept-%s-%s.png' % (title.replace(' ', '_'), wid)))], capture_output=True)
            click_field(wid)
            subprocess.run(['xdotool', 'key', 'Return'], capture_output=True)
            done.add((title, wid))
            print('accepted', title, wid, flush=True)
    time.sleep(1)
