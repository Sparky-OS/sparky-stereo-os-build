#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Run as an ordinary user in a container, with the real problems engine and catalogs."""
import argparse
import json
import os
import signal
import time
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('script', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
script = args.script.resolve()
results = []
# This child belongs to the test. Only its PID is ever signalled.
(args.output / 'daemon-signals').unlink(missing_ok=True)
daemon = subprocess.Popen(['/usr/bin/python3', '-c',
    'import signal,time,sys; signal.signal(signal.SIGHUP, lambda *_: open(sys.argv[1], "a").write("HUP\\n")); print("ready",flush=True); time.sleep(300)', str(args.output.resolve()/'daemon-signals')],
    stdout=subprocess.PIPE, text=True)
assert daemon.stdout.readline().strip() == 'ready'

STUB = '''#!/usr/bin/python3
import os, pathlib, sys, signal
name = pathlib.Path(sys.argv[0]).name
mode = os.environ['TEST_MODE']
with open(os.environ['TEST_CALLS'], 'a') as stream:
    stream.write(name + ' ' + ' '.join(sys.argv[1:]) + '\\n')
if name == 'kreadconfig6':
    if mode == 'read-fail':
        print('injected kreadconfig6 error', file=sys.stderr)
        sys.exit(17)
    os.execv('/usr/bin/kreadconfig6', sys.argv)
if name == 'kwriteconfig6':
    if mode == 'write-fail':
        print('injected kwriteconfig6 error', file=sys.stderr)
        sys.exit(21)
    os.execv('/usr/bin/kwriteconfig6', sys.argv)
if name == 'gsettings':
    value = pathlib.Path(os.environ['TEST_CALLS']).parent / sys.argv[3]
    if sys.argv[1] == 'get':
        print(repr(value.read_text() if value.exists() else 'Before'))
        sys.exit(0)
    if mode == 'lost-' + sys.argv[3]:
        print('injected dconf commit error', file=sys.stderr)
        sys.exit(0)
    if mode == 'gsettings-' + sys.argv[3]:
        print('injected gsettings error', file=sys.stderr)
        sys.exit(23)
    value.write_text(sys.argv[4])
    sys.exit(0)
if name == 'pgrep':
    if mode == 'live-daemon':
        print(os.environ['TEST_PID'])
        sys.exit(0)
    if mode == 'pgrep-fail':
        print('injected pgrep error', file=sys.stderr)
        sys.exit(2)
    if mode == 'reload-fail':
        print('2147483647')
        sys.exit(0)
    sys.exit(1)
if name == 'pkill':
    if mode == 'live-daemon':
        os.kill(int(os.environ['TEST_PID']), signal.SIGHUP)
        sys.exit(0)
    print('injected xsettingsd reload error', file=sys.stderr)
    sys.exit(1)
'''

cases = [
    ('works', 'live-daemon', True, None, None),
    ('no-daemon', 'works', True, None, None),
    ('no-config', 'works', False, None, None),
    ('read-fail', 'read-fail', True, 'scheme', 'injected kreadconfig6 error'),
    ('unreadable', 'works', True, 'scheme', 'Cannot read'),
    ('write-fail', 'write-fail', True, 'gtk-3.0-theme', 'injected kwriteconfig6 error'),
    ('gsettings-theme', 'gsettings-gtk-theme', True, 'gsettings-theme', 'injected gsettings error'),
    ('gsettings-colour', 'gsettings-color-scheme', True, 'gsettings-colour', 'injected gsettings error'),
    ('lost-theme', 'lost-gtk-theme', True, 'gsettings-theme-verify', 'injected dconf commit error'),
    ('lost-colour', 'lost-color-scheme', True, 'gsettings-colour-verify', 'injected dconf commit error'),
    ('reload-fail', 'reload-fail', True, 'xsettings-reload', 'No such process'),
    ('pgrep-fail', 'pgrep-fail', True, 'xsettings-reload', 'injected pgrep error'),
]
schemes = {
    'SparkyStereoOxygen': ('Sparky-Stereo-Oxygen', 'false'),
    'SparkyStereoOxygenDark': ('Sparky-Stereo-Oxygen-Dark', 'true'),
    'Oxygen': ('Sparky-Stereo-Oxygen', 'false'),
    'OxygenDark': ('Sparky-Stereo-Oxygen-Dark', 'true'),
    'kubabbar-glass': ('Kubabbar-Glass', 'false'),
    'BreezeDark': ('Breeze-Dark', 'true'),
    'BreezeLight': ('Breeze', 'false'),
    'CustomDark': ('Breeze-Dark', 'true'),
    'Custom': ('Breeze', 'false'),
    '': ('Breeze', 'false'),
}
cases += [('scheme-' + scheme, 'works', True, None, None) for scheme in schemes]
with tempfile.TemporaryDirectory(prefix='gtk-sync-tests-') as temporary:
    root = Path(temporary)
    stubs = root / 'bin'
    stubs.mkdir()
    for name in ['kreadconfig6', 'kwriteconfig6', 'gsettings', 'pgrep', 'pkill']:
        p = stubs / name
        p.write_text(STUB)
        p.chmod(0o755)
    for name, mode, xsettings, key, error in cases:
        work = root / name
        config = work / 'config'
        config.mkdir(parents=True)
        source = config / 'kdeglobals'
        scheme = name.removeprefix('scheme-') if name.startswith('scheme-') else 'OxygenDark'
        expected_theme, expected_dark = schemes[scheme]
        source.write_text('[General]\nColorScheme=' + scheme + '\n')
        if name == 'unreadable':
            source.chmod(0)
        if xsettings:
            p = config / 'xsettingsd/xsettingsd.conf'
            p.parent.mkdir()
            p.write_text('Net/ThemeName "Before"\n')
        env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(config),
                   XDG_CONFIG_DIRS=str(work/'defaults'), XDG_STATE_HOME=str(work/'state'),
                   PATH=str(stubs)+':'+os.environ['PATH'], TEST_MODE=mode,
                   TEST_CALLS=str(work/'calls'), TEST_PID=str(daemon.pid), LC_ALL='C.UTF-8', LANGUAGE='en')
        for variable in ['DISPLAY', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'XAUTHORITY']:
            env.pop(variable, None)
        run = subprocess.run(['sh', str(script)], env=env, text=True, capture_output=True)
        listed = subprocess.run(['sparky-stereo-problems', 'list', '--json', 'sparky-stereo-gtk'],
                                env=env, text=True, capture_output=True)
        records = json.loads(listed.stdout)
        # Keep the engine's own JSON and original script output, not a reconstruction.
        (args.output / (name+'.json')).write_text(listed.stdout)
        (args.output / (name+'.log')).write_text(run.stdout+run.stderr)
        checks = {'list_exit_zero': listed.returncode == 0}
        if key:
            checks.update(nonzero_exit=run.returncode != 0,
                          own_error_visible=error in run.stdout+run.stderr,
                          kept=any(r['key'] == key for r in records),
                          no_success='GTK synchronization completed' not in run.stdout and 'sparky-stereo-gtk-sync: scheme=' not in run.stdout)
        else:
            checks.update(exit_zero=run.returncode == 0, no_problem=not records,
                          theme=all('gtk-theme-name=' + expected_theme + '\n' in (config/('gtk-'+v)/'settings.ini').read_text() for v in ('3.0', '4.0')),
                          dark=all('gtk-application-prefer-dark-theme=' + expected_dark + '\n' in (config/('gtk-'+v)/'settings.ini').read_text() for v in ('3.0', '4.0')))
            if name == 'works':
                checks['daemon_alive'] = daemon.poll() is None
                for _ in range(100):
                    if (args.output/'daemon-signals').exists():
                        break
                    time.sleep(0.01)
                checks['signal_received'] = (args.output/'daemon-signals').exists()
            else:
                checks['skip_said'] = ('not running' if xsettings else 'No xsettingsd configuration') in run.stdout+run.stderr
        if key == 'scheme':
            checks['no_settings_written'] = not (config/'gtk-3.0/settings.ini').exists()
        if key:
            # A successful retry must remove that exact failed step from the real engine.
            source.chmod(0o600)
            env['TEST_MODE'] = 'works'
            if key == 'xsettings-reload':
                env['TEST_MODE'] = 'live-daemon'
            if key:
                retry = subprocess.run(['sh', str(script)], env=env, text=True, capture_output=True)
                after = subprocess.run(['sparky-stereo-problems', 'list', '--json', 'sparky-stereo-gtk'],
                                       env=env, text=True, capture_output=True, check=True)
                retry_ok = retry.returncode == 0 and not json.loads(after.stdout)
                (args.output/(name+'-retry.json')).write_text(after.stdout)
                checks['retry_clears'] = retry_ok
        result = dict(case=name, exit=run.returncode, list_exit=listed.returncode,
                      checks=checks, passed=all(checks.values()))
        results.append(result)
        print(json.dumps(result))
daemon.terminate()
daemon.wait(timeout=5)
(args.output/'results.json').write_text(json.dumps(results, indent=2)+'\n')
failed = sum(not r['passed'] for r in results)
print(f'{len(results)} cases; {failed} failed')
raise SystemExit(bool(failed))
