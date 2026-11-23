# SPDX-License-Identifier: GPL-3.0-or-later
"""Bounded KDE operations for the operator-run A10 benchmark."""
import csv
import json
import re
import subprocess
import time
from pathlib import Path

OUTPUTS = ('eDP-1', 'HDMI-A-1')
ROTATIONS = {1: 'none', 2: 'left', 4: 'inverted', 8: 'right', 16: 'flipped',
             32: 'flipped90', 64: 'flipped180', 128: 'flipped270'}


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE, timeout=20)


def outputs():
    return json.loads(command('kscreen-doctor', '-j'))


def check_dimming(text):
    # Check disabled outputs too: any reported dimming invalidates the run.
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    values = [float(x) for x in re.findall(r'dimming to\s+([0-9.]+)%', text)]
    if not values or len(values) != text.count('dimming to') or any(abs(x - 100) > .001 for x in values):
        raise RuntimeError(f'Output dimming is not proven clear: {values}')


def check_dpms(text, expected=()):
    rows = re.findall(r'^dpms mode for screen (.+): (on|off)$', text, re.MULTILINE)
    if not rows or len(rows) != text.count('dpms mode for screen ') or any(state != 'on' for _, state in rows):
        raise RuntimeError('Display power is not proven on: '+text.strip())
    states = dict(rows)
    if not set(expected) <= states.keys():
        raise RuntimeError('Missing DPMS state for an active output')
    return states


def wake_outputs():
    assert_unlocked()
    command('kscreen-doctor', '--dpms', 'on')
    expected = [o['name'] for o in outputs()['outputs'] if o['enabled']]
    return check_dpms(command('kscreen-doctor', '--dpms', 'show'), expected)


def place_until_fullscreen(root, pid, output, tag, observer, guard):
    assert_unlocked()
    for attempt in range(8):
        place(root, pid, output, f'{tag}-{attempt}')
        guard.wait(3)
        try:
            verify_window(observer, output)
            return
        except RuntimeError:
            if attempt == 7:
                raise


def mode_ids(snapshot):
    by_name = {o['name']: o for o in snapshot['outputs'] if o['connected']}
    if not all(name in by_name for name in OUTPUTS):
        raise RuntimeError('Connect both A10 outputs before starting')
    wanted = [('HDMI-A-1', 3, 1920, 1080, 30), ('eDP-1', 5, 1366, 768, 60)]
    result = {}
    for name, stereo, width, height, refresh in wanted:
        matches = [m for m in by_name[name]['modes'] if m['stereo3D'] == stereo
                   and m['viewSize'] == dict(width=width, height=height)
                   and abs(m['refreshRate'] - refresh) < .1]
        # A TV may offer the same frame-packing mode at 30.00 and 29.97 Hz: take the one nearest the
        # reviewed rate and refuse only a true tie.
        matches.sort(key=lambda m: abs(m['refreshRate'] - refresh))
        if not matches or (len(matches) > 1 and abs(matches[0]['refreshRate'] - refresh) == abs(matches[1]['refreshRate'] - refresh)):
            raise RuntimeError(f'Expected one reviewed {name} mode, found {matches}')
        result[name] = matches[0]['id']
    return result


def setup_args(ids, extended):
    args = []
    for name in OUTPUTS:
        enabled = extended or name == 'HDMI-A-1'
        args.append(f'output.{name}.{"enable" if enabled else "disable"}')
        if enabled:
            args += [f'output.{name}.mode.{ids[name]}', f'output.{name}.scale.1',
                     f'output.{name}.rotation.none', f'output.{name}.mirror.none',
                     f'output.{name}.position.{"1366,0" if extended and name == "HDMI-A-1" else "0,0"}']
    return args


def restore_args(snapshot):
    connected = [o for o in snapshot['outputs'] if o['connected']]
    names = {o['id']: o['name'] for o in connected}
    args = []
    for o in connected:
        name = o['name']
        # Restore mode and position while enabled, then return its enable state.
        if o.get('currentModeId'):
            args += [f'output.{name}.enable', f'output.{name}.mode.{o["currentModeId"]}',
                     f'output.{name}.scale.{o["scale"]}',
                     f'output.{name}.rotation.{ROTATIONS[o["rotation"]]}',
                     f'output.{name}.position.{o["pos"]["x"]},{o["pos"]["y"]}',
                     f'output.{name}.mirror.{names.get(o.get("replicationSource"), "none")}']
        args.append(f'output.{name}.{"enable" if o["enabled"] else "disable"}')
    return args


def verify_setup(snapshot, ids, extended):
    by_name = {o['name']: o for o in snapshot['outputs']}
    for name in OUTPUTS:
        o = by_name[name]
        expected = extended or name == 'HDMI-A-1'
        if o['enabled'] != expected:
            raise RuntimeError(f'{name}: enable state did not apply')
        if expected and (o['currentModeId'] != ids[name] or o['scale'] != 1
                         or o['rotation'] != 1 or o.get('replicationSource', 0) != 0
                         or o['pos'] != dict(x=1366 if extended and name == 'HDMI-A-1' else 0, y=0)):
            raise RuntimeError(f'{name}: requested mode/placement did not apply')


def tail(path, limit=65536):
    with Path(path).open('rb') as handle:
        handle.seek(0, 2)
        size = handle.tell()
        handle.seek(max(0, size-limit))
        blob = handle.read().decode()
    lines = blob.splitlines()
    return lines[1:] if size > limit else lines


def latest_flip(path):
    rows = list(csv.reader(tail(path)))
    for row in reversed(rows):
        if len(row) == 9 and row[1].isdigit():
            return int(row[1])/1e9
    return 0


def verify_window(path, output):
    rows = list(csv.reader(tail(path)))
    rows = [r for r in rows if len(r) == 6 and r[0] == 'window']
    if not rows or rows[-1][3] != '1' or rows[-1][5] != output or time.monotonic()-int(rows[-1][1])/1e9 > 4:
        raise RuntimeError(f'Fullscreen placement not observed on {output}')


def assert_unlocked():
    for line in command('loginctl', 'list-sessions', '--no-legend').splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[3] == 'seat0':
            hint = command('loginctl', 'show-session', parts[0], '-p', 'LockedHint').strip()
            if hint != 'LockedHint=no':
                raise RuntimeError('The desktop session is locked: unlock it before the bench')
            return
    raise RuntimeError('No seat0 session found')


def place(root, pid, output, tag):
    script = root/'place.js'
    script.write_text('for (const w of workspace.windowList()) {\n'
        f' if (w.pid == {pid} && w.normalWindow) {{\n'
        f'  const o = workspace.screens.find(s => s.name == {json.dumps(output)});\n'
        '  if (o) workspace.sendClientToScreen(w, o);\n'
        '  w.fullScreen = true; workspace.activeWindow = w;\n }\n}\n')
    sid = command('qdbus6', 'org.kde.KWin', '/Scripting',
                  'org.kde.kwin.Scripting.loadScript', str(script), tag).strip()
    if not sid.isdigit():
        raise RuntimeError(f'KWin did not load placement script: {sid}')
    try:
        command('qdbus6', 'org.kde.KWin', '/Scripting/Script'+sid, 'org.kde.kwin.Script.run')
    finally:
        command('qdbus6', 'org.kde.KWin', '/Scripting', 'org.kde.kwin.Scripting.unloadScript', tag)


class Guard:
    def __init__(self, root, pid, logdir):
        self.root, self.pid, self.logdir = root, pid, logdir
        self.identity = self.process_identity()
        self.player = None
        self.expected = None
        self.last_activity = 0
        self.last_geometry = 0

    def process_identity(self):
        return Path(f'/proc/{self.pid}/stat').read_text().rsplit(')', 1)[1].split()[19]

    def activity(self):
        command('qdbus6', 'org.freedesktop.ScreenSaver', '/ScreenSaver',
                'org.freedesktop.ScreenSaver.SimulateUserActivity')
        self.last_activity = time.monotonic()

    def check(self):
        if self.process_identity() != self.identity:
            raise RuntimeError('KWin restarted during the run')
        if self.player and self.player.poll() is not None:
            raise RuntimeError(f'Bino exited early: {self.player.returncode}')
        assert_unlocked()
        expected = ('eDP-1', 'HDMI-A-1') if self.expected and self.expected[1] else ('HDMI-A-1',) if self.expected else ()
        dpms = check_dpms(command('kscreen-doctor', '--dpms', 'show'), expected)
        text = command('kscreen-doctor', '-o')
        check_dimming(text)
        with (self.root/'awake.jsonl').open('a') as handle:
            handle.write(json.dumps(dict(monotonic=time.monotonic(), dpms=dpms, dimming=re.findall(r'dimming to\s+([0-9.]+)%', text)))+'\n')
        if self.expected and time.monotonic()-self.last_geometry > 15:
            verify_setup(outputs(), *self.expected)
            self.last_geometry = time.monotonic()
        if time.monotonic()-self.last_activity > 15:
            self.activity()

    def wait(self, seconds):
        end = time.monotonic()+seconds
        while True:
            self.check()
            delay = min(2, end-time.monotonic())
            if delay <= 0:
                return
            time.sleep(delay)


def verify_restore(original, current):
    after = {o['name']: o for o in current['outputs']}
    fields = ('enabled', 'currentModeId', 'pos', 'scale', 'rotation', 'replicationSource')
    for before in original['outputs']:
        if before['connected']:
            actual = after.get(before['name'], {})
            for field in fields:
                if before.get(field) != actual.get(field):
                    raise RuntimeError(f"Restoration differs for {before['name']}: {field}")
