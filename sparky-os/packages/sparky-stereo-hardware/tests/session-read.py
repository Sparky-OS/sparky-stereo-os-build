#!/usr/bin/python3
"""Unprivileged session environment test; real KConfig and engine, no display.

Usage: session-read.py SCRIPT LANGDIR OUT
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

script, languages, out = map(Path, sys.argv[1:])
assert os.geteuid() != 0, 'Unreadability must be tested as a person'
out.mkdir(parents=True, exist_ok=True)
failed = 0


def check(ok, description):
    global failed
    print(('PASS ' if ok else 'FAIL ') + description)
    failed += not ok


with tempfile.TemporaryDirectory() as temp:
    work = Path(temp)
    for folder in ('config','system','vendors','bin','state'):
        (work/folder).mkdir()
    for vendor in ('50_mesa.json','10_nvidia.json'):
        (work/'vendors'/vendor).write_text('{}')
    (work/'opengl.conf').write_text('desktop=nvidia\nopengl=zink\n')
    catalog = work/'catalog'
    subprocess.run(['sparky-stereo-problems','catalog','sparky-stereo-hardware',str(languages),str(catalog),'--subject','LOCAL1'],check=True)
    env = dict(PATH=f'{work}/bin:/usr/bin:/bin', HOME=str(work), XDG_CONFIG_HOME=str(work/'config'),
               XDG_CONFIG_DIRS=str(work/'system'), XDG_STATE_HOME=str(work/'state'), LC_ALL='C.UTF-8',
               SPARKY_STEREO_OPENGL_CONF=str(work/'opengl.conf'), SPARKY_STEREO_EGL_VENDORS=str(work/'vendors'),
               SPARKY_STEREO_PROBLEMS_CATALOG=f'{catalog}:/usr/lib/systemd/catalog')
    runner = 'set -eu; . "$1"; python3 -c \'import json,os; print(json.dumps({k:os.environ.get(k) for k in ["MESA_LOADER_DRIVER_OVERRIDE","SPARKY_STEREO_OPENGL"]}))\''
    for case in ('default', 'disabled', 'failed-command', 'unreadable-person', 'unreadable-system', 'recovered', 'own-choice', 'not-nvidia'):
        for f in (work/'config/startkderc',work/'system/startkderc',work/'bin/kreadconfig6'):
            if f.exists():
                f.chmod(0o644)
                f.unlink()
        case_env = env.copy()
        if case == 'disabled':
            (work/'config/startkderc').write_text('[General]\nsystemdBoot=false\n')
        elif case == 'failed-command':
            f = work/'bin/kreadconfig6'
            f.write_text('#!/bin/sh\necho true\necho "kreadconfig injected failure" >&2\nexit 17\n')
            f.chmod(0o755)
        elif case.startswith('unreadable-'):
            f=work/('config' if case.endswith('person') else 'system')/'startkderc'
            f.write_text('[General]\nsystemdBoot=false\n')
            f.chmod(0)
        elif case == 'own-choice':
            case_env['MESA_LOADER_DRIVER_OVERRIDE']='custom'
        elif case == 'not-nvidia':
            (work/'opengl.conf').write_text('desktop=mesa\n')
        p=subprocess.run(['sh','-c',runner,'session',str(script)],env=case_env,text=True,capture_output=True)
        (out/f'{case}.stderr').write_text(p.stderr)
        (out/f'{case}.stdout').write_text(p.stdout)
        (out/f'{case}.exit').write_text(str(p.returncode)+'\n')
        check(p.returncode==0,f'{case}: sourced script keeps desktop shell running')
        applied=json.loads(p.stdout) if p.returncode==0 else {}
        expected='zink' if case in ('default','recovered') else 'custom' if case=='own-choice' else None
        check(applied.get('MESA_LOADER_DRIVER_OVERRIDE')==expected,f'{case}: override is {expected}')
        listing=subprocess.run(['sparky-stereo-problems','list','--json','sparky-stereo-hardware'],env=env,text=True,capture_output=True,check=True)
        (out/f'{case}.json').write_text(listing.stdout)
        records=json.loads(listing.stdout)
        if case=='failed-command' or case.startswith('unreadable-'):
            check(len(records)==1 and records[0].get('key')=='systemd-boot',f'{case}: kept in person store')
            if case=='failed-command':
                check('kreadconfig injected failure' in p.stderr and records and records[0].get('status')==17,'failed-command: original error and status survive')
            else:
                check('Cannot read' in p.stderr and 'startkderc' in p.stderr,f'{case}: unreadable file named')
        else:
            check(records==[],f'{case}: no unresolved problem')
        if case=='disabled':
            check('systemdBoot=false' in p.stderr,'disabled: skip explained')
print(f'{failed} failed checks')
sys.exit(bool(failed))
