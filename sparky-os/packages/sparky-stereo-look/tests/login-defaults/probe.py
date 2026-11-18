#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Read installed defaults and the live panel in a private Plasma login."""
import json
import os
from pathlib import Path
import shutil
import subprocess

case = Path(os.environ['CASE'])
rows = [
    ('ksmserverrc', ['General'], 'loginMode', 'emptySession', 'restorePreviousLogout'),
    ('ksmserverrc', ['General'], 'confirmLogout', 'false', 'true'),
    ('kdeglobals', ['Sounds'], 'Theme', 'oxygen', 'ocean'),
    ('powerdevilrc', ['BatteryManagement'], 'BatteryLowLevel', '25', '10'),
    ('powerdevilrc', ['BatteryManagement'], 'BatteryCriticalLevel', '15', '5'),
    ('powerdevilrc', ['BatteryManagement'], 'BatteryCriticalAction', '8', '1'),
    ('powerdevilrc', ['AC', 'Display'], 'DisplayBrightness', '100', '80'),
    ('powerdevilrc', ['AC', 'Display'], 'UseProfileSpecificDisplayBrightness', 'true', 'false'),
    ('powerdevilrc', ['Battery', 'Display'], 'UseProfileSpecificDisplayBrightness', 'true', 'false'),
    ('powerdevilrc', ['AC', 'Keyboard'], 'KeyboardBrightness', '100', '20'),
    ('powerdevilrc', ['LowBattery', 'Keyboard'], 'KeyboardBrightness', '11', '25'),
    ('powerdevilrc', ['AC', 'Keyboard'], 'UseProfileSpecificKeyboardBrightness', 'true', 'false'),
    ('powerdevilrc', ['Battery', 'Keyboard'], 'UseProfileSpecificKeyboardBrightness', 'true', 'false'),
    ('powerdevilrc', ['LowBattery', 'Keyboard'], 'UseProfileSpecificKeyboardBrightness', 'true', 'false'),
]
user = os.environ.get('EXPECT_USER') == '1'
checks = []
for filename, groups, key, default, override in rows:
    command = ['kreadconfig6', '--file', filename]
    for group in groups:
        command.extend(['--group', group])
    command.extend(['--key', key])
    read = subprocess.run(command, text=True, capture_output=True)
    actual = read.stdout.strip()
    wanted = override if user else default
    checks.append(dict(file=filename, groups=groups, key=key, actual=actual,
                       expected=wanted, passed=actual == wanted))
qdbus = shutil.which('qdbus6') or shutil.which('qdbus')
if not qdbus:
    raise SystemExit('qdbus is missing')
script = '''JSON.stringify(panels().map(function(p) {
    return {id: p.id, widgets: p.widgets().map(function(w) { return w.type; })};
}))'''
live = subprocess.run([qdbus, 'org.kde.plasmashell', '/PlasmaShell',
                       'org.kde.PlasmaShell.evaluateScript', script],
                      text=True, capture_output=True)
(case / 'panel-dbus.txt').write_text(live.stdout + live.stderr)
panels = json.loads(live.stdout) if live.returncode == 0 else []
launchers = [widget for panel in panels for widget in panel['widgets']
             if widget in ('org.kde.plasma.kicker', 'org.kde.plasma.kickoff')]
wanted = ['org.kde.plasma.kickoff' if user else 'org.kde.plasma.kicker']
checks.append(dict(key='live panel launchers', actual=launchers, expected=wanted,
                   passed=launchers == wanted))
for check in checks:
    print(('PASS' if check['passed'] else 'FAIL'), check['key'],
          repr(check['actual']), 'expected', repr(check['expected']), flush=True)
(case / 'defaults.json').write_text(json.dumps(dict(checks=checks, panels=panels), indent=2) + '\n')
# Retain the configuration for the upgrade/personalisation case before run-case removes the home.
subprocess.run(['tar', '-C', os.environ['HOME'], '-cf', str(case / 'user-config.tar'), '.config'], check=True)
raise SystemExit(0 if all(c['passed'] for c in checks) else 1)
