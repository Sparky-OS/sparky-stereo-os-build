#!/usr/bin/python3
"""Unlisted packages retain failures; removed packages still lose stale records.

Run only as root in a disposable container with the engine installed.
OUT keeps commands, their exit codes and output, and each check's result.
The notifier's reader is exercised through its actual ssp_list_json C ABI.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

assert os.geteuid() == 0, 'Run only as root inside a disposable test container'
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
engine = 'sparky-stereo-problems'
store = Path('/var/lib/sparky-stereo-problems')
unlisted = 'sparky-test-unlisted'
fresh = 'sparky-test-first-install'
events = []
checks = []


def call(command, label, uid=0):
    env = dict(os.environ, LANG='C.UTF-8', HOME='/tmp',
               XDG_STATE_HOME='/tmp/unlisted-package-state')
    for key in ('LANGUAGE', 'LC_ALL', 'SPARKY_STEREO_PROBLEMS_CATALOG',
                'SPARKY_STEREO_ROOT'):
        env.pop(key, None)

    def person():
        os.setgroups([])
        os.setgid(uid)
        os.setuid(uid)

    p = subprocess.run(command, capture_output=True, text=True, env=env,
                       preexec_fn=person if uid else None)
    (out / f'{label}.stdout').write_text(p.stdout)
    (out / f'{label}.stderr').write_text(p.stderr)
    events.append(dict(label=label, command=command, uid=uid, status=p.returncode))
    (out / 'commands.json').write_text(json.dumps(events, indent=2) + '\n')
    return p


def check(label, condition):
    checks.append(dict(label=label, passed=bool(condition)))
    print(('PASS  ' if condition else 'FAIL  ') + label, flush=True)
    (out / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')


def record(package, key):
    path = store / f'{package}_{key}.json'
    if not path.exists():
        return {}
    text = path.read_text()
    (out / f'{package}_{key}.json').write_text(text)
    return json.loads(text)


def listed(package, label, uid=0, abi=False):
    if abi:
        # This Python wrapper calls ssp_list_json, also used by Notifier::rescan.
        command = ['python3', '-c',
                   'import json,sys,sparky_stereo_problems as p; '
                   'print(json.dumps(p.list(sys.argv[1])))', package]
    else:
        command = [engine, 'list', '--json', package]
    p = call(command, label, uid)
    assert p.returncode == 0, (label, p.stderr)
    return json.loads(p.stdout)


for package in (unlisted, fresh):
    p = call(['dpkg-query', '-W', '-f=${Status}', package], f'initial-{package}')
    assert p.returncode != 0, f'{package} already exists; use a fresh container'

p = call([engine, 'run', '--machine', unlisted, 'run', 'LOCAL999',
          '--', 'sh', '-c', 'exit 7'], 'unlisted-run')
check('run returns the child status 7', p.returncode == 7)
r = record(unlisted, 'run')
check('unlisted run retains its command, exit status and repair',
      r.get('status') == 7 and r.get('command') == ['sh', '-c', 'exit 7']
      and r.get('repair') == [['sh', '-c', 'exit 7']])
check('unlisted run says package, step and status on stderr without a bare catalog key',
      unlisted in p.stderr and 'run' in p.stderr and '7' in p.stderr
      and 'LOCAL999' not in p.stderr)

p = call([engine, 'run', '--machine', '--quiet', unlisted, 'quiet', 'LOCAL999',
          '--', 'sh', '-c', 'exit 9'], 'unlisted-quiet')
r = record(unlisted, 'quiet')
check('quiet run writes its record before any reader visits',
      p.returncode == 9 and r.get('status') == 9)
text = r.get('text_en', '')
check('missing catalog saves readable English naming package, step and status',
      unlisted in text and 'quiet' in text and '9' in text and 'LOCAL999' not in text)
items = listed(unlisted, 'unlisted-person-abi', uid=1000, abi=True)
check('the notifier reader sees an unlisted failure as a person',
      any(x['key'] == 'quiet' for x in items))
check('a person reader cannot unlink the machine record',
      (store / f'{unlisted}_quiet.json').exists())
items = listed(unlisted, 'unlisted-root')
check('root listing retains an unlisted failure and its record',
      any(x['key'] == 'quiet' for x in items)
      and (store / f'{unlisted}_quiet.json').exists())

english = 'Preparing the package failed; retry the preparation.'
p = call([engine, 'keep', '--machine', '--status', '5', unlisted, 'keep', english],
         'unlisted-keep')
r = record(unlisted, 'keep')
check('keep immediately stores and says the English text supplied by its caller',
      p.returncode == 0 and english in p.stderr and r.get('text_en') == english)
items = listed(unlisted, 'keep-person-abi', uid=1000, abi=True)
check('the notifier reader sees keep before the package is installed',
      any(x['key'] == 'keep' and x['text'] == english for x in items))
items = listed(unlisted, 'keep-root')
check('root listing preserves the unlisted keep record',
      any(x['key'] == 'keep' for x in items)
      and (store / f'{unlisted}_keep.json').exists())

with tempfile.TemporaryDirectory(prefix='unlisted-package-') as work:
    work = Path(work)
    work.chmod(0o755)
    os.chown(work, 1000, 1000)
    tree = work / 'package'
    (tree / 'DEBIAN').mkdir(parents=True)
    (tree / 'DEBIAN/control').write_text(f'''Package: {fresh}
Version: 1
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Pre-Depends: sparky-stereo-problems
Description: disposable first install retention test
''')
    lang = work / 'lang'
    lang.mkdir()
    (lang / 'en').write_text('LOCAL1="First install test"\n'
                           'LOCAL2="%s failed with exit status %s; retry preparation."\n')
    catalog = tree / 'usr/lib/systemd/catalog'
    catalog.mkdir(parents=True)
    p = call([engine, 'catalog', fresh, str(lang), str(catalog), '--subject', 'LOCAL1'],
             'fixture-catalog')
    assert p.returncode == 0, p.stderr
    (tree / 'DEBIAN/preinst').write_text(f'''#!/bin/sh
set -e
test ! -e /var/lib/dpkg/info/{fresh}.list
test ! -e /usr/lib/systemd/catalog/{fresh}.catalog
echo 'PREINST: no file list and no catalog' >&2
sparky-stereo-problems run --machine {fresh} prepare LOCAL2 -- sh -c 'exit 11' && status=0 || status=$?
echo "PREINST: engine returned $status" >&2
test "$status" = 11
if test -e /var/lib/sparky-stereo-problems/{fresh}_prepare.json; then
    echo 'PREINST: record exists' >&2
fi
exit 0
''')
    (tree / 'DEBIAN/preinst').chmod(0o755)
    p = call(['dpkg-deb', '--root-owner-group', '--build', str(tree), str(work / 'probe.deb')],
             'fixture-build', uid=1000)
    assert p.returncode == 0, p.stderr
    p = call(['dpkg', '-i', str(work / 'probe.deb')], 'first-install')
    assert p.returncode == 0, p.stderr
    check('real first-install preinst runs without its file list and catalog',
          'PREINST: no file list and no catalog' in p.stderr
          and 'PREINST: engine returned 11' in p.stderr)
    check('preinst keeps and says the failure before unpack',
          'PREINST: record exists' in p.stderr and fresh + ':' in p.stderr)
    check('dpkg post-invoke observes the first installation without an explicit reader',
          record(fresh, 'prepare').get('package_seen') is True)
    items = listed(fresh, 'installed-person-abi', uid=1000, abi=True)
    check('after install the notifier reader sees the preinst failure with its catalog',
          any(x['key'] == 'prepare' and x['status'] == 11
              and 'failed with exit status 11' in x['text'] for x in items))
    p = call([engine, 'keep', '--machine', fresh, 'removed', 'LOCAL2', 'preparation', '13'],
             'installed-keep')
    assert p.returncode == 0, p.stderr
    check('installed-package control stores a failure and lists it',
          any(x['key'] == 'removed' for x in listed(fresh, 'installed-control')))
    hook = Path('/etc/dpkg/dpkg.cfg.d/sparky-stereo-problems')
    saved_hook = work / 'hook'
    if hook.exists():
        hook.rename(saved_hook)
    p = call(['dpkg', '--remove', fresh], 'remove')
    assert p.returncode == 0, p.stderr
    check('real removal removes the package file list and catalog',
          not Path(f'/var/lib/dpkg/info/{fresh}.list').exists()
          and not Path(f'/usr/lib/systemd/catalog/{fresh}.catalog').exists())
    check('a reader unable to unlink still lists the removed package record',
          any(x['key'] == 'removed' for x in listed(fresh, 'removed-person-abi', uid=1000, abi=True)))
    check('root collection clears a really removed package record',
          listed(fresh, 'removed-root') == []
          and not (store / f'{fresh}_removed.json').exists())
    check('after root cleanup the notifier reader no longer sees the removed package',
          listed(fresh, 'removed-person-after-root', uid=1000, abi=True) == [])
    if saved_hook.exists():
        saved_hook.rename(hook)
    p = call(['dpkg', '-i', str(work / 'probe.deb')], 'hook-install')
    assert p.returncode == 0, p.stderr
    hook_had_record = record(fresh, 'prepare').get('status') == 11
    p = call(['dpkg', '--remove', fresh], 'hook-remove')
    assert p.returncode == 0, p.stderr
    check('dpkg post-invoke clears a preinst failure after real removal without an explicit reader',
          hook_had_record and not (store / f'{fresh}_prepare.json').exists())

p = call([engine, 'clear', '--all', unlisted], 'explicit-clear')
check('explicit clear remains available for unlisted failures',
      p.returncode == 0 and listed(unlisted, 'cleared') == [])
p = call(['dpkg', '--audit'], 'audit')
check('dpkg finishes without incomplete package state', p.returncode == 0 and not p.stdout.strip())
failed = sum(not x['passed'] for x in checks)
print(f'{len(checks) - failed} passed; {failed} failed')
sys.exit(min(failed, 255))
