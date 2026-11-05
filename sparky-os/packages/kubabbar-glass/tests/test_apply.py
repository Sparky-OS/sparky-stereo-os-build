#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""ORDER 346f-5 (audit 343 U39): kubabbar-glass-minimize and kubabbar-glass-style say what they could not save or apply.

Run as an ordinary user in a container with the real problems engine and its catalogs:
    test_apply.py TREE OUTPUT
TREE holds bin/ and lang/ side by side (this package's source, or a published payload laid out the same way).
KWin is a stub of org.kde.kwin.Effects that keeps a list of loaded effects; the signal to programs is a stub too.
The configuration files are written by the real kwriteconfig6 and read by the real kreadconfig6.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

tree = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)

DBUS = '''#!/usr/bin/python3
import os, sys, pathlib
mode = os.environ['TEST_MODE']
state = pathlib.Path(os.environ['TEST_STATE'])
loaded = set(state.read_text().split()) if state.exists() else {'squash'}
args = [a for a in sys.argv[1:] if not a.startswith('--')]
if mode == 'nobus':
    print('Failed to open connection to "session" message bus: Could not parse server address', file=sys.stderr)
    sys.exit(1)
if '--type=signal' in sys.argv:
    sys.exit(0)
member = [a for a in args if a.startswith('org.kde.kwin.Effects.')][0].rsplit('.', 1)[1]
name = [a for a in args if a.startswith('string:')][0][7:]
if member == 'unloadEffect':
    if mode != 'stale':
        loaded.discard(name)
elif member == 'loadEffect':
    if mode != 'refuse':
        loaded.add(name)
    print('   ' + ('true' if name in loaded else 'false'))
elif member == 'isEffectLoaded':
    print('   ' + ('true' if name in loaded else 'false'))
state.write_text(' '.join(sorted(loaded)))
'''
WRITE = '''#!/bin/sh
echo "injected kwriteconfig6 error" >&2
exit 21
'''
results = []
with tempfile.TemporaryDirectory(prefix='apply-tests-') as temporary:
    root = Path(temporary)
    stubs = root / 'stubs'
    stubs.mkdir()
    (stubs / 'dbus-send').write_text(DBUS)
    (stubs / 'dbus-send').chmod(0o755)
    (stubs / 'kwriteconfig6-fail').write_text(WRITE)
    (stubs / 'kwriteconfig6-fail').chmod(0o755)
    plugins = root / 'plugins/styles'
    plugins.mkdir(parents=True)
    for plugin in ('libkvantum.so', 'oxygen6.so', 'breeze6.so'):
        (plugins / plugin).write_text('')
    real_write = subprocess.run(['sh', '-c', 'command -v kwriteconfig6'], text=True, capture_output=True).stdout.strip()

    def run(case, script, arg, mode, write_fail=False, plugin_path=True, reuse=None):
        work = reuse or (root / case)
        (work / 'config').mkdir(parents=True, exist_ok=True)
        bindir = root / ('bin-fail' if write_fail else 'bin-ok')
        bindir.mkdir(exist_ok=True)
        link = bindir / 'kwriteconfig6'
        if not link.exists() and not link.is_symlink():
            link.symlink_to(stubs / 'kwriteconfig6-fail' if write_fail else real_write)
        path = ':'.join([str(bindir), str(stubs), os.environ['PATH']])
        env = dict(os.environ, HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'), XDG_CONFIG_DIRS=str(work / 'defaults'),
                   XDG_STATE_HOME=str(work / 'state'), PATH=path, TEST_MODE=mode, TEST_STATE=str(work / 'kwin'),
                   LC_ALL='C.UTF-8', LANGUAGE='en')
        if plugin_path:
            env['QT_PLUGIN_PATH'] = str(root / 'plugins')
        for variable in ('DISPLAY', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'XAUTHORITY'):
            env.pop(variable, None)
        proc = subprocess.run(['sh', str(tree / 'bin' / script), arg], env=env, text=True, capture_output=True, cwd=work)
        listed = subprocess.run(['sparky-stereo-problems', 'list', '--json'], env=env, text=True, capture_output=True)
        records = json.loads(listed.stdout) if listed.returncode == 0 and listed.stdout.strip() else []
        (output / (case + '.log')).write_text(proc.stdout + proc.stderr)
        (output / (case + '.json')).write_text(listed.stdout)
        return proc, records, work

    def conf(work, name, group, key):
        proc = subprocess.run(['kreadconfig6', '--file', str(work / 'config' / name), '--group', group, '--key', key],
                              text=True, capture_output=True)
        return proc.stdout.strip()

    def record(case, checks):
        passed = all(checks.values())
        results.append(dict(case=case, checks=checks, passed=passed))
        print(json.dumps(dict(case=case, checks=checks, passed=passed)))

    # ---- minimise -------------------------------------------------------------------------------------------------
    p, r, w = run('min-ok', 'kubabbar-glass-minimize', 'magiclamp', 'ok')
    record('min-ok', dict(exit0=p.returncode == 0, done='Minimise effect set to magiclamp' in p.stdout, no_problem=not r,
                          saved=conf(w, 'kwinrc', 'Plugins', 'magiclampEnabled') == 'true'))
    p, r, w = run('min-writefail', 'kubabbar-glass-minimize', 'magiclamp', 'ok', write_fail=True)
    out = p.stdout + p.stderr
    record('min-writefail', dict(nonzero=p.returncode != 0, reason_shown='injected kwriteconfig6 error' in out,
                                 kept=any(x['key'] == 'minimize' for x in r), no_done='effect set to' not in out))
    p, r, w = run('min-nobus', 'kubabbar-glass-minimize', 'magiclamp', 'nobus')
    out = p.stdout + p.stderr
    record('min-nobus', dict(nonzero=p.returncode != 0, reason_shown='message bus' in out, next_login_said='next login' in out,
                             kept=any(x['key'] == 'minimize' for x in r), no_done='effect set to' not in out,
                             saved_kept=conf(w, 'kwinrc', 'Plugins', 'magiclampEnabled') == 'true'))
    p2, r2, _ = run('min-nobus-retry', 'kubabbar-glass-minimize', 'magiclamp', 'ok', reuse=w)
    record('min-retry-clears', dict(exit0=p2.returncode == 0, cleared=not r2, done='effect set to magiclamp' in p2.stdout))
    p, r, w = run('min-refused', 'kubabbar-glass-minimize', 'magiclamp', 'refuse')
    out = p.stdout + p.stderr
    record('min-refused', dict(nonzero=p.returncode != 0, reason_shown='not loaded' in out,
                               kept=any(x['key'] == 'minimize' for x in r), no_done='effect set to' not in out))
    p, r, w = run('min-stale', 'kubabbar-glass-minimize', 'magiclamp', 'stale')
    out = p.stdout + p.stderr
    record('min-stale', dict(nonzero=p.returncode != 0, reason_shown='still loaded' in out,
                             kept=any(x['key'] == 'minimize' for x in r), no_done='effect set to' not in out))
    # ---- style ----------------------------------------------------------------------------------------------------
    p, r, w = run('style-ok', 'kubabbar-glass-style', 'oxygen', 'ok')
    record('style-ok', dict(exit0=p.returncode == 0, done='Application style set to oxygen' in p.stdout, no_problem=not r,
                            saved=conf(w, 'kdeglobals', 'KDE', 'widgetStyle') == 'Oxygen'))
    p, r, w = run('style-breeze', 'kubabbar-glass-style', 'breeze', 'ok')
    record('style-breeze', dict(exit0=p.returncode == 0, saved=conf(w, 'kdeglobals', 'KDE', 'widgetStyle') == 'Breeze', no_problem=not r))
    p, r, w = run('style-fusion', 'kubabbar-glass-style', 'fusion', 'ok', plugin_path=False)
    record('style-fusion-needs-no-plugin', dict(exit0=p.returncode == 0, saved=conf(w, 'kdeglobals', 'KDE', 'widgetStyle') == 'Fusion'))
    p, r, w = run('style-noplugin', 'kubabbar-glass-style', 'oxygen', 'ok', plugin_path=False)
    out = p.stdout + p.stderr
    record('style-noplugin', dict(nonzero=p.returncode != 0, package_named='kde-style-oxygen-qt6' in out,
                                  kept=any(x['key'] == 'style' for x in r), nothing_written=conf(w, 'kdeglobals', 'KDE', 'widgetStyle') == '',
                                  no_done='Application style set' not in out))
    p, r, w = run('style-writefail', 'kubabbar-glass-style', 'oxygen', 'ok', write_fail=True)
    out = p.stdout + p.stderr
    record('style-writefail', dict(nonzero=p.returncode != 0, reason_shown='injected kwriteconfig6 error' in out,
                                   kept=any(x['key'] == 'style' for x in r), no_done='Application style set' not in out))
    p, r, w = run('style-nobus', 'kubabbar-glass-style', 'oxygen', 'nobus')
    out = p.stdout + p.stderr
    record('style-nobus', dict(nonzero=p.returncode != 0, reason_shown='could not be told' in out and 'message bus' in out,
                               kept=any(x['key'] == 'style' for x in r), no_done='Application style set' not in out,
                               saved_kept=conf(w, 'kdeglobals', 'KDE', 'widgetStyle') == 'Oxygen'))
    p2, r2, _ = run('style-nobus-retry', 'kubabbar-glass-style', 'oxygen', 'ok', reuse=w)
    record('style-retry-clears', dict(exit0=p2.returncode == 0, cleared=not r2))

failed = sum(not x['passed'] for x in results)
(output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
print(f'{len(results)} cases; {failed} failed')
raise SystemExit(bool(failed))
