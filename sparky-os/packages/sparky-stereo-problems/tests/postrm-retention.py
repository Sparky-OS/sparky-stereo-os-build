#!/usr/bin/python3
"""Real dpkg lifecycle, only in a disposable container with the engine installed.

Run as root for dpkg; fixture build and person queries use uid/gid 1000.
--legacy uses the old package-owned keep call, making the purge assertion red
on 0.1.0 rather than merely testing an unsupported option. OUT keeps evidence.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('out', type=Path)
parser.add_argument('--legacy', action='store_true')
args = parser.parse_args()
assert os.geteuid() == 0, 'Run only as root inside a disposable test container'
args.out.mkdir(parents=True, exist_ok=True)
pkg = 'sparky-test-postrm-retention'
engine = 'sparky-stereo-problems'
owner = pkg if args.legacy else engine
key = 'motd' if args.legacy else f'after-removal:{pkg}:motd'
events = []


def call(command, label, uid=0, expected=0, env=None):
    env = dict(os.environ if env is None else env)
    if uid:
        env['HOME'] = '/tmp'
        env['XDG_STATE_HOME'] = '/tmp/postrm-retention-person-state'
    def person():
        os.setgroups([])
        os.setgid(uid)
        os.setuid(uid)
    p = subprocess.run(command, capture_output=True, text=True,
                       preexec_fn=person if uid else None, env=env)
    (args.out / f'{label}.stdout').write_text(p.stdout)
    (args.out / f'{label}.stderr').write_text(p.stderr)
    events.append(dict(label=label, command=command, uid=uid, status=p.returncode))
    (args.out / 'commands.json').write_text(json.dumps(events, indent=2) + '\n')
    assert p.returncode == expected, (label, p.returncode, p.stderr)
    return p.stdout


with tempfile.TemporaryDirectory(prefix='postrm-retention-') as work:
    work = Path(work)
    work.chmod(0o755)
    os.chown(work, 1000, 1000)
    tree = work / 'package'
    (tree / 'DEBIAN').mkdir(parents=True)
    (tree / 'etc').mkdir()
    (tree / 'etc/postrm-retention.conf').write_text('test\n')
    (tree / 'DEBIAN/conffiles').write_text('/etc/postrm-retention.conf\n')
    (tree / 'DEBIAN/control').write_text(f'''Package: {pkg}
Version: 1
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Depends: sparky-stereo-problems
Description: disposable postrm retention test
''')
    command = ['cp', str(work / 'source'), str(work / 'restored')]
    cmdjson = json.dumps(command)
    flag = '' if args.legacy else '--after-removal'
    (tree / 'DEBIAN/postrm').write_text(f'''#!/bin/sh
set -e
case "$1" in
remove|purge|abort-install)
    if [ "$1" = remove ]; then sparky-stereo-problems clear --all {pkg}; fi
    if error=$(cp {work}/source {work}/restored 2>&1); then
        sparky-stereo-problems clear --machine {owner} {key}
    else
        status=$?
        printf '%s\\n' "$error" >&2
        sparky-stereo-problems keep --machine {flag} --status "$status" \\
            --command '{cmdjson}' --repair '{cmdjson}' --output "$error" \\
            {pkg} motd 'restore MOTD'
    fi
    ;;
esac
exit 0
''')
    (tree / 'DEBIAN/postrm').chmod(0o755)
    call(['dpkg-deb', '--root-owner-group', '--build', str(tree), str(work / 'probe.deb')], 'build', uid=1000)
    call(['dpkg', '-i', str(work / 'probe.deb')], 'install')
    call(['dpkg', '--remove', pkg], 'remove')
    records = json.loads(call([engine, 'list', '--json', owner], 'remove-person', uid=1000))
    assert any(r['key'] == key for r in records), records
    call(['dpkg', '--purge', pkg], 'purge')
    for uid in (1000, 0):
        records = json.loads(call([engine, 'list', '--json', owner], f'purge-{uid}', uid=uid))
        matching = [r for r in records if r['key'] == key]
        assert len(matching) == 1, 'Unresolved postrm failure disappeared after purge'
    r = matching[0]
    assert r['package'] == engine and r['message'] == 'LOCAL67', r
    assert r['data']['package'] == pkg and r['data']['step'] == 'motd', r
    assert r['data']['command'] == command and 'cannot stat' in r['data']['error'], r
    assert r['status'] == 1 and r['repair'] == [command], r
    call([engine, 'clear', '--all', pkg], 'clear-removed-package')
    assert any(r['key'] == key for r in json.loads(call([engine, 'list', '--json'], 'still-owned')))
    for lang in ('en', 'de', 'es', 'pl', 'pt_BR', 'fr', 'ja', 'ko', 'zh_CN', 'zh_TW'):
        env = dict(os.environ, LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8', LANGUAGE=lang)
        text = call([engine, 'text', '--machine', engine, key], f'language-{lang}', uid=1000, env=env)
        assert pkg in text and 'restore MOTD' in text and 'cannot stat' in text and 'LOCAL67' not in text, text
    call([engine, 'repair', '--machine', engine, key], 'repair-still-fails', expected=1)
    assert any(r['key'] == key for r in json.loads(call([engine, 'list', '--json'], 'failed-repair-stays')))
    (work / 'source').write_text('restored MOTD\n')
    call([engine, 'repair', '--machine', engine, key], 'repair')
    assert (work / 'restored').read_text() == 'restored MOTD\n'
    assert not any(r['key'] == key for r in json.loads(call([engine, 'list', '--json'], 'repaired-person', uid=1000)))
    keep = [engine, 'keep', '--machine', '--after-removal', '--command', cmdjson,
            '--repair', cmdjson, '--status', '1', '--output', 'test error', pkg, 'motd', 'restore MOTD']
    call(keep, 'keep-again')
    call([engine, 'clear', '--machine', engine, key], 'explicit-clear')
    assert not any(r['key'] == key for r in json.loads(call([engine, 'list', '--json'], 'cleared-person', uid=1000)))
    # A new failure after purge is not a stale record from before removal.
    call([engine, 'keep', '--machine', pkg, 'ordinary', 'old failure'], 'ordinary-keep')
    assert any(r['key'] == 'ordinary' for r in json.loads(call([engine, 'list', '--json', pkg], 'ordinary-retained')))
    call([engine, 'clear', '--all', pkg], 'ordinary-clear')
    assert json.loads(call([engine, 'list', '--json', pkg], 'ordinary-cleared')) == []
    call([engine, 'keep', '--after-removal', pkg, 'x', 'step'], 'missing-evidence', expected=2)
    call([engine, 'keep', '--person', '--after-removal', pkg, 'x', 'step'], 'wrong-scope', uid=1000, expected=2)
    assert not call(['dpkg', '--audit'], 'audit').strip()
    print('PASS: removal, purge, person/root visibility, nine languages, failed/successful repair, clear, new failure after purge and invalid calls')
