#!/usr/bin/python3
"""Collection controls in isolated SPARKY_STEREO_ROOT fixtures, inside a container."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

assert os.geteuid() == 0, 'Run in a disposable container as root'
binary = 'sparky-stereo-problems'
package = 'sparky-test-lifecycle'
checks = 0


def check(label, condition):
    global checks
    assert condition, label
    checks += 1
    print('PASS  ' + label, flush=True)


with tempfile.TemporaryDirectory(prefix='collection-tests-') as path:
    root = Path(path)
    root.chmod(0o755)
    info = root / 'var/lib/dpkg/info'
    info.mkdir(parents=True)
    status = root / 'var/lib/dpkg/status'
    status.write_text('')
    state = root / 'person'
    state.mkdir(mode=0o700)
    os.chown(state, 1000, 1000)
    env = dict(os.environ, SPARKY_STEREO_ROOT=str(root), LANG='C.UTF-8',
               SPARKY_STEREO_PROBLEMS_CATALOG='/usr/lib/systemd/catalog',
               XDG_STATE_HOME=str(state))

    def call(*args, uid=0):
        def person():
            os.setgroups([])
            os.setgid(uid)
            os.setuid(uid)
        p = subprocess.run([binary, *args], env=env, capture_output=True, text=True,
                           preexec_fn=person if uid else None)
        assert p.returncode == 0, (args, p.returncode, p.stderr)
        return p.stdout

    def records(uid=0):
        return json.loads(call('list', '--json', package, uid=uid))

    def keep(key, uid=0):
        return call('keep', '--person' if uid else '--machine', package, key, 'LOCAL999', uid=uid)

    def file(key):
        return root / 'var/lib/sparky-stereo-problems' / f'{package}_{key}.json'

    keep('early')
    check('initial absence retains the failure', len(records()) == 1)
    # Any Debian architecture, not a fixed amd64/i386 shortlist.
    listing = info / f'{package}:arm64.list'
    listing.touch()
    before = json.loads(file('early').read_text())
    records()
    after = json.loads(file('early').read_text())
    check('a later root reader observes installation on another architecture', after['package_seen'])
    check('observing installation changes no failure or hide identity',
          {k: v for k, v in before.items() if k != 'package_seen'} ==
          {k: v for k, v in after.items() if k != 'package_seen'})
    listing.unlink()
    status.write_text(f'Package: {package}\nStatus: install reinstreq half-installed\nArchitecture: arm64\n\n')
    check('an interrupted installation without a file list is not removal', len(records()) == 1)
    status.unlink()
    check('an unavailable dpkg database does not authorize removal', len(records()) == 1)
    status.write_text('')
    check('an unprivileged reader keeps a record it cannot unlink visible', len(records(uid=1000)) == 1)
    check('a writer clears a record only after observed presence disappears', records() == [])

    listing.touch()
    keep('again')
    listing.unlink()
    keep('again')
    check('a new failure after removal resets its installation observation',
          not json.loads(file('again').read_text())['package_seen'] and len(records()) == 1)
    call('clear', '--all', package)

    keep('legacy')
    old = json.loads(file('legacy').read_text())
    del old['package_seen']
    old['text_en'] = 'LOCAL999'
    file('legacy').write_text(json.dumps(old))
    rows = records()
    check('old records without lifecycle evidence are retained', len(rows) == 1)
    check('old bare-key English is rendered as a useful explanation',
          package in rows[0]['text'] and 'legacy' in rows[0]['text'] and 'LOCAL999' not in rows[0]['text'])
    call('clear', '--all', package)

    listing.touch()
    keep('conffiles')
    status.write_text(f'Package: {package}\nStatus: deinstall ok config-files\nArchitecture: arm64\n\n')
    check('removed config-files state expires despite a residual file list', records() == [])
    status.write_text('')

    keep('readonly', uid=1000)
    listing.unlink()
    folder = state / 'sparky-stereo-problems'
    folder.chmod(0o500)
    check('a person with an unwritable store still sees the stale record',
          any(r['key'] == 'readonly' for r in records(uid=1000)))
    folder.chmod(0o700)
    check('the same person clears it when the store becomes writable', records(uid=1000) == [])

    listing.touch()
    keep('foreign-root')
    listing.unlink()
    hook = Path('/etc/dpkg/dpkg.cfg.d/sparky-stereo-problems').read_text().split('post-invoke=', 1)[1].strip()
    for label, extra in (('another root', {'DPKG_ROOT': '/foreign'}),
                         ('another database', {'DPKG_ROOT': '', 'DPKG_ADMINDIR': '/foreign-db'})):
        p = subprocess.run(['/bin/sh', '-c', hook], env=dict(env, **extra), capture_output=True, text=True)
        check(f'a transaction in {label} does not collect this system',
              p.returncode == 0 and file('foreign-root').exists())
    p = subprocess.run(['/bin/sh', '-c', hook], env=dict(env, DPKG_ROOT='', DPKG_ADMINDIR='/var/lib/dpkg'),
                       capture_output=True, text=True)
    check('the standard-root hook collects a confirmed removal', p.returncode == 0 and not file('foreign-root').exists())

    call('keep', '--machine', '--details', '{"text_en":"Caller supplied English."}', package, 'english', 'LOCAL999')
    check('explicit English in details survives a missing catalog', records()[0]['text'] == 'Caller supplied English.')
    for language in ('en', 'de', 'fr', 'pl', 'pt_BR', 'ja', 'ko', 'zh_CN', 'zh_TW'):
        p = subprocess.run([binary, 'say', 'sparky-stereo-problems', 'LOCAL69', package, 'prepare', '7'],
                           env=dict(env, LANG='en_US.UTF-8', LANGUAGE=language), capture_output=True, text=True)
        check(f'generic explanation in {language} has every field',
              p.returncode == 0 and package in p.stderr and 'prepare' in p.stderr
              and '7' in p.stderr and 'LOCAL69' not in p.stderr)
print(f'{checks} passed; 0 failed')
