#!/usr/bin/python3
"""Exercise the generated postrm in a disposable container (root maintscript).

Usage: postrm.py POSTRM OUT. dpkg-divert is stubbed; actual diversion lifecycle
is verified separately in the installed-package upgrade/removal proof.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

script, out = map(Path, sys.argv[1:])
out.mkdir(parents=True, exist_ok=True)
assert os.geteuid() == 0, 'Disposable container only'
engine = 'sparky-stereo-problems'
key = 'after-removal:sparky-stereo-console:motd'
motd = Path('/etc/motd')
saved = motd.read_bytes() if motd.exists() else None
failed = 0


def check(ok, text):
    global failed
    print(('PASS ' if ok else 'FAIL ') + text)
    failed += not ok


with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    temp.chmod(0o755)
    (temp / 'dpkg-divert').write_text('#!/bin/sh\nexit 0\n')
    (temp / 'cp').write_text('''#!/bin/sh
echo called >>"$CALLS"
if [ "$FAIL" = yes ]; then echo 'copy injected failure' >&2; exit 1; fi
exec /bin/cp "$@"
''')
    (temp / 'logger').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >>"$JOURNAL"\n')
    for file in temp.iterdir():
        file.chmod(0o755)
    try:
        for case in ('works', 'exists', 'fails', 'no-engine'):
            motd.unlink(missing_ok=True)
            (temp / 'calls').unlink(missing_ok=True)
            if case == 'exists':
                motd.write_text('administrator MOTD\n')
            subprocess.run([engine, 'clear', '--machine', engine, key], check=True)
            env = dict(os.environ, PATH=str(temp) + ('' if case == 'no-engine' else ':/usr/bin:/bin'),
                       CALLS=str(temp/'calls'), JOURNAL=str(temp/'journal'),
                       FAIL='yes' if case in ('fails','no-engine') else 'no')
            p = subprocess.run(['/bin/sh', str(script), 'remove'], env=env, capture_output=True, text=True)
            (out/f'{case}.stdout').write_text(p.stdout)
            (out/f'{case}.stderr').write_text(p.stderr)
            (out/f'{case}.exit').write_text(str(p.returncode)+'\n')
            listing = subprocess.run([engine, 'list', '--json', engine], capture_output=True, text=True, check=True)
            (out/f'{case}.json').write_text(listing.stdout)
            records = [r for r in json.loads(listing.stdout) if r.get('key') == key]
            check(p.returncode == 0, f'{case}: postrm completes')
            if case == 'works':
                check(motd.read_bytes() == Path('/usr/share/base-files/motd').read_bytes(), 'works: restores base-files MOTD')
            elif case == 'exists':
                check(motd.read_text() == 'administrator MOTD\n' and not (temp/'calls').exists(), 'exists: preserves administrator file and skips copy')
            elif case == 'fails':
                check('copy injected failure' in p.stderr, 'fails: command error shown')
                check(len(records)==1 and records[0]['status']==1 and records[0]['data']['package']=='sparky-stereo-console', 'fails: engine owns unresolved repair')
            else:
                check('copy injected failure' in p.stderr and 'could not be saved' in p.stderr, 'no engine: embedded terminal text')
                check((temp/'journal').exists() and 'copy injected failure' in (temp/'journal').read_text(), 'no engine: journal attempted with error and repair')
            if case != 'fails':
                check(records == [], f'{case}: no false engine record')
        # Existing engine-owned failure clears when a later attempt works.
        subprocess.run([engine,'keep','--machine','--after-removal','--command','["false"]','--repair','["true"]','--status','1','--output','old error','sparky-stereo-console','motd','cp'], check=True)
        env.update(PATH=str(temp)+':/usr/bin:/bin', FAIL='no')
        p = subprocess.run(['/bin/sh',str(script),'purge'],env=env,capture_output=True,text=True)
        records=json.loads(subprocess.check_output([engine,'list','--json',engine],text=True))
        check(p.returncode==0 and not any(r.get('key')==key for r in records),'retry: successful restoration clears the engine-owned problem')
    finally:
        motd.unlink(missing_ok=True)
        if saved is not None:
            motd.write_bytes(saved)
        subprocess.run([engine,'clear','--machine',engine,key],check=True)
print(f'{failed} failed checks')
sys.exit(bool(failed))
