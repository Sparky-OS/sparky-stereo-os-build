#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Exercise the real Konsole and target apt in an isolated Xvfb/D-Bus session.

corefonts-gui.py HELPER TARGET EVIDENCE_DIR [accept|refuse|close]
TARGET must be a disposable unpacked image with the candidate apt source and shared hook.
Never run against a person's installed system or desktop.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
import time

helper, target, evidence, *rest = sys.argv[1:]
choice = rest[0] if rest else 'accept'
assert choice in ('accept', 'refuse', 'close')
out = Path(evidence)
out.mkdir(parents=True, exist_ok=True)

def call(destination, path, method, *args):
    return subprocess.check_output(['dbus-send', '--session', '--print-reply', '--dest=' + destination,
                                    path, method, *args], text=True, stderr=subprocess.DEVNULL)

def keys(text=None):
    # Type through Xvfb's input device, as the person does; D-Bus is only used to observe text.
    windows = subprocess.check_output(['xdotool', 'search', '--onlyvisible', '--class', 'konsole'], text=True).splitlines()
    subprocess.run(['xdotool', 'windowfocus', '--sync', windows[0]], check=True)
    if text is not None:
        subprocess.run(['xdotool', 'key', '--clearmodifiers', 'ctrl+u'], check=True)
        subprocess.run(['xdotool', 'type', '--clearmodifiers', '--delay', '1', text], check=True)
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'Return'], check=True)

with (out / ('terminal-launch-' + choice + '.log')).open('w') as log:
    environment = dict(os.environ, INSTALLER_LANG='en', LANG='C.UTF-8', DEBIAN_FRONTEND='noninteractive')
    process = subprocess.Popen([helper, '--window', target], env=environment, stdout=log, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 240
    service = None
    answered = False
    paused = False
    more_text = None
    captures = []
    try:
        while time.monotonic() < deadline and process.poll() is None:
            if service is None:
                names = call('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus.ListNames')
                found = re.findall(r'string "(org\.kde\.konsole[^\"]*)"', names)
                if not found:
                    time.sleep(0.1)
                    continue
                service = found[0]
                (out / ('terminal-introspection-' + choice + '.txt')).write_text(
                    call(service, '/Sessions/1', 'org.freedesktop.DBus.Introspectable.Introspect'))
            try:
                text = call(service, '/Sessions/1', 'org.kde.konsole.Session.getAllDisplayedText', 'boolean:true')
            except subprocess.CalledProcessError:
                time.sleep(0.1)
                continue
            if not captures or text != captures[-1]:
                captures.append(text)
            if re.search(r'\[More\]\s*"\s*$', text) and text != more_text:
                keys()
                more_text = text
            if 'Do you accept the Microsoft EULA?' in text and not answered:
                assert not (Path(target) / 'usr/share/fonts/truetype/msttcorefonts/Arial.ttf').exists()
                if choice == 'close':
                    subprocess.run(['xdotool', 'search', '--class', 'konsole', 'windowkill'], check=True)
                else:
                    keys('yes' if choice == 'accept' else 'no')
                answered = True
            if 'Press Enter to return to the installer.' in text and not paused:
                keys()
                paused = True
            time.sleep(0.1)
        status = process.wait(timeout=5)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
        (out / ('terminal-text-' + choice + '.txt')).write_text('\n\n'.join(captures))
assert answered, 'the real terminal never presented the licence question'
if choice == 'close':
    assert status != 0, 'closing the terminal must not report a completed installation'
    assert not list((Path(target) / 'usr/share/fonts/truetype/msttcorefonts').glob('*.ttf'))
elif choice == 'accept':
    assert status == 0 and paused
    family = subprocess.check_output(['chroot', target, 'fc-match', '-f', '%{family}', 'Arial'], text=True)
    assert family == 'Arial', family
else:
    assert status == 0 and paused
    assert not list((Path(target) / 'usr/share/fonts/truetype/msttcorefonts').glob('*.ttf'))
    assert any('dpkg-reconfigure ttf-mscorefonts-installer' in text for text in captures)
print(f'PASS real Konsole {choice}: exit={status}, licence question visible, target checked')
