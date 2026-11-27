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
if name == 'dconf':
    # dconf prints a key's stored value, and nothing for a key nobody has set
    value = pathlib.Path(os.environ['TEST_CALLS']).parent / pathlib.Path(sys.argv[2]).name
    if mode == 'dconf-fail':
        print('injected dconf error', file=sys.stderr)
        sys.exit(29)
    if value.exists():
        print(value.read_text())
    sys.exit(0)
if name == 'gsettings':
    value = pathlib.Path(os.environ['TEST_CALLS']).parent / sys.argv[3]
    if sys.argv[1] == 'get':
        print(repr(value.read_text() if value.exists() else 'Before'))
        sys.exit(0)
    if sys.argv[1] == 'reset':
        value.unlink(missing_ok=True)
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
    'kubabbar-glass-9': ('Kubabbar-Glass-9', 'false'),
    'kubabbar-glass-9-graphite': ('Kubabbar-Glass-9-Graphite', 'false'),
    'kubabbar-glass-9-ivy': ('Kubabbar-Glass-9-Ivy', 'false'),
    'kubabbar-glass-9-rose': ('Kubabbar-Glass-9-Rose', 'false'),
    'kubabbar-glass-9-gold': ('Kubabbar-Glass-9-Gold', 'false'),
    'kubabbar-glass-9-teal': ('Kubabbar-Glass-9-Teal', 'false'),
    'kubabbar-glass-9-unknown': ('Breeze', 'false'),
    'BreezeDark': ('Breeze-Dark', 'true'),
    'BreezeLight': ('Breeze', 'false'),
    'CustomDark': ('Breeze-Dark', 'true'),
    'Custom': ('Breeze', 'false'),
    '': ('Breeze', 'false'),
}
cases += [('scheme-' + scheme, 'works', True, None, None) for scheme in schemes]
# Kubabbar Glass 9's arrow choice (kubabbar-glass-9rc): apart is the Apart theme, together or no choice the theme itself
arrow_cases = {'arrows-apart': ('kubabbar-glass-9-rose', 'apart', 'Kubabbar-Glass-9-Rose-Apart'),
               'arrows-apart-default': ('kubabbar-glass-9', 'apart', 'Kubabbar-Glass-9-Apart'),
               'arrows-together': ('kubabbar-glass-9-teal', 'together', 'Kubabbar-Glass-9-Teal'),
               'arrows-other-look': ('kubabbar-glass', 'apart', 'Kubabbar-Glass'),
               'arrows-unreadable': ('kubabbar-glass-9', 'apart', None)}
cases += [('gtk2-file-absent', 'works', True, None, None)]
cases += [(name, 'works', True, 'arrows' if name == 'arrows-unreadable' else None,
           'Cannot read' if name == 'arrows-unreadable' else None) for name in arrow_cases]
with tempfile.TemporaryDirectory(prefix='gtk-sync-tests-') as temporary:
    root = Path(temporary)
    stubs = root / 'bin'
    stubs.mkdir()
    for name in ['kreadconfig6', 'kwriteconfig6', 'gsettings', 'dconf', 'pgrep', 'pkill']:
        p = stubs / name
        p.write_text(STUB)
        p.chmod(0o755)
    for name, mode, xsettings, key, error in cases:
        work = root / name
        config = work / 'config'
        config.mkdir(parents=True)
        source = config / 'kdeglobals'
        scheme = name.removeprefix('scheme-') if name.startswith('scheme-') else 'OxygenDark'
        arrows_file = None
        if name in arrow_cases:
            scheme, arrows, theme_9 = arrow_cases[name]
            arrows_file = config / 'kubabbar-glass-9rc'
            arrows_file.write_text('[Scrolling]\nArrows=' + arrows + '\n')
            if name == 'arrows-unreadable':
                arrows_file.chmod(0)
        expected_theme, expected_dark = schemes[scheme]
        if arrows_file and theme_9:
            expected_theme = theme_9
        source.write_text('[General]\nColorScheme=' + scheme + '\n')
        # KDE's GTK module's GTK 2 file, with its own theme name and a line of the person's that must stay
        if name != 'gtk2-file-absent':
            (work / '.gtkrc-2.0').write_text('gtk-theme-name="Breeze"\ngtk-cursor-blink=1\n')
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
            gtk2 = (work / '.gtkrc-2.0').read_text() if (work / '.gtkrc-2.0').exists() else ''
            checks['gtk2_theme'] = 'gtk-theme-name="' + expected_theme + '"\n' in gtk2 and gtk2.count('gtk-theme-name=') == 1
            if name != 'gtk2-file-absent':
                checks['gtk2_other_lines_kept'] = 'gtk-cursor-blink=1\n' in gtk2
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
        if key in ('scheme', 'arrows'):
            checks['no_settings_written'] = not (config/'gtk-3.0/settings.ini').exists()
        if key:
            # A successful retry must remove that exact failed step from the real engine.
            source.chmod(0o600)
            if arrows_file:
                arrows_file.chmod(0o600)
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

    # Kubabbar Glass 9's bars always show: overlay scrolling off for its themes only, a person's own value kept (row 147)
    def ini(config, version):
        p = config / ('gtk-' + version) / 'settings.ini'
        lines = p.read_text().splitlines() if p.exists() else []
        values = [line.split('=', 1)[1] for line in lines if line.startswith('gtk-overlay-scrolling=')]
        return values[-1] if values else None

    def sync(work, config, scheme, mode='works'):
        (config / 'kdeglobals').write_text('[General]\nColorScheme=' + scheme + '\n')
        env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(config), XDG_CONFIG_DIRS=str(work/'defaults'),
                   XDG_STATE_HOME=str(work/'state'), PATH=str(stubs)+':'+os.environ['PATH'], TEST_MODE=mode,
                   TEST_CALLS=str(work/'calls'), TEST_PID=str(daemon.pid), LC_ALL='C.UTF-8', LANGUAGE='en')
        for variable in ['DISPLAY', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'XAUTHORITY']:
            env.pop(variable, None)
        done = subprocess.run(['sh', str(script)], env=env, text=True, capture_output=True)
        listed = subprocess.run(['sparky-stereo-problems', 'list', '--json', 'sparky-stereo-gtk'],
                                env=env, text=True, capture_output=True, check=True)
        return done, json.loads(listed.stdout)

    def own_ini(config, version, value):
        d = config / ('gtk-' + version)
        d.mkdir(parents=True, exist_ok=True)
        (d / 'settings.ini').write_text('[Settings]\ngtk-overlay-scrolling=' + value + '\n')

    overlay_cases = ['overlay-9-fresh', 'overlay-9-own-ini', 'overlay-9-own-dconf', 'overlay-9-twice', 'overlay-leave',
                     'overlay-leave-changed', 'overlay-other-look', 'overlay-record-unreadable', 'overlay-dconf-fail']
    for name in overlay_cases:
        work = root / name
        config = work / 'config'
        config.mkdir(parents=True)
        dconf_value = work / 'overlay-scrolling'
        record = work / 'state/sparky-stereo-gtk/overlay-scrolling.written'
        checks = {}
        if name == 'overlay-9-own-ini':
            own_ini(config, '4.0', 'true')
        if name in ('overlay-9-own-dconf', 'overlay-other-look'):
            dconf_value.write_text('true')
        if name == 'overlay-other-look':
            own_ini(config, '3.0', 'true')
        first, records = sync(work, config, 'OxygenDark' if name == 'overlay-other-look' else 'kubabbar-glass-9-ivy',
                              'dconf-fail' if name == 'overlay-dconf-fail' else 'works')
        log = first.stdout + first.stderr
        if name == 'overlay-record-unreadable':
            record.chmod(0)
            first, records = sync(work, config, 'kubabbar-glass-9')
            log = first.stdout + first.stderr
            checks.update(nonzero_exit=first.returncode != 0, kept=any(r['key'] == 'overlay-scrolling' for r in records),
                          own_error_visible='Cannot read' in log)
            record.chmod(0o600)
            retry, after = sync(work, config, 'kubabbar-glass-9')
            checks['retry_clears'] = retry.returncode == 0 and not after
        elif name == 'overlay-dconf-fail':
            checks.update(nonzero_exit=first.returncode != 0, own_error_visible='injected dconf error' in log,
                          kept=any(r['key'] == 'overlay-scrolling-read' for r in records),
                          theme_still_applied='gtk-theme-name=Kubabbar-Glass-9-Ivy\n' in (config/'gtk-4.0/settings.ini').read_text())
            retry, after = sync(work, config, 'kubabbar-glass-9-ivy')
            checks.update(retry_clears=retry.returncode == 0 and not after,
                          retry_writes=ini(config, '3.0') == 'false' and dconf_value.read_text() == 'false')
        else:
            checks.update(exit_zero=first.returncode == 0, no_problem=not records)
            if name == 'overlay-9-fresh':
                checks.update(ini_3=ini(config, '3.0') == 'false', ini_4=ini(config, '4.0') == 'false',
                              gsettings=dconf_value.read_text() == 'false',
                              recorded=record.read_text() == 'gtk-3.0 false\ngtk-4.0 false\ngsettings false\n')
            elif name == 'overlay-9-own-ini':
                checks.update(own_kept=ini(config, '4.0') == 'true', ini_3=ini(config, '3.0') == 'false',
                              gsettings=dconf_value.read_text() == 'false',
                              recorded=record.read_text() == 'gtk-3.0 false\ngsettings false\n')
            elif name == 'overlay-9-own-dconf':
                checks.update(own_kept=dconf_value.read_text() == 'true', ini_3=ini(config, '3.0') == 'false',
                              recorded=record.read_text() == 'gtk-3.0 false\ngtk-4.0 false\n')
            elif name == 'overlay-9-twice':
                second, again = sync(work, config, 'kubabbar-glass-9')
                checks.update(second_exit_zero=second.returncode == 0 and not again, ini_3=ini(config, '3.0') == 'false',
                              ini_4=ini(config, '4.0') == 'false', gsettings=dconf_value.read_text() == 'false',
                              recorded=record.read_text() == 'gtk-3.0 false\ngtk-4.0 false\ngsettings false\n')
            elif name == 'overlay-leave':
                second, again = sync(work, config, 'OxygenDark')
                checks.update(second_exit_zero=second.returncode == 0 and not again, ini_3_removed=ini(config, '3.0') is None,
                              ini_4_removed=ini(config, '4.0') is None, gsettings_reset=not dconf_value.exists(),
                              record_removed=not record.exists(),
                              theme_kept='gtk-theme-name=Sparky-Stereo-Oxygen-Dark\n' in (config/'gtk-3.0/settings.ini').read_text())
            elif name == 'overlay-leave-changed':
                p = config / 'gtk-3.0/settings.ini'
                p.write_text(p.read_text().replace('gtk-overlay-scrolling=false', 'gtk-overlay-scrolling=true'))
                dconf_value.write_text('true')
                second, again = sync(work, config, 'OxygenDark')
                checks.update(second_exit_zero=second.returncode == 0 and not again, own_ini_kept=ini(config, '3.0') == 'true',
                              own_dconf_kept=dconf_value.read_text() == 'true', ours_removed=ini(config, '4.0') is None,
                              record_removed=not record.exists())
            elif name == 'overlay-other-look':
                checks.update(own_ini_kept=ini(config, '3.0') == 'true', own_dconf_kept=dconf_value.read_text() == 'true',
                              nothing_written=ini(config, '4.0') is None and not record.exists())
        (args.output / (name + '.log')).write_text(log)
        result = dict(case=name, exit=first.returncode, checks=checks, passed=all(checks.values()))
        results.append(result)
        print(json.dumps(result))
daemon.terminate()
daemon.wait(timeout=5)
(args.output/'results.json').write_text(json.dumps(results, indent=2)+'\n')
failed = sum(not r['passed'] for r in results)
print(f'{len(results)} cases; {failed} failed')
raise SystemExit(bool(failed))
