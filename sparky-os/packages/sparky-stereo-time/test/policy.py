#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Installed-payload policy oracle. Run as uid 1000 in a disposable container.
Usage: policy.py EXTRACTED_PACKAGE EVIDENCE_DIRECTORY [--runtime]
Requires chrony, the problems engine, ucf and fakeroot.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root, evidence = map(lambda p: Path(p).resolve(), sys.argv[1:3])
evidence.mkdir(parents=True, exist_ok=True)
base = root / 'usr'
program = base / 'bin/sparky-stereo-time'
helper = base / 'lib/sparky-stereo-time/chrony-config'
failed = 0


def check(name, result):
    global failed
    print(('PASS ' if result else 'FAIL ') + name, flush=True)
    failed += not result


def run(cmd, env, **kwargs):
    return subprocess.run(list(map(str, cmd)), env=env, text=True, capture_output=True, **kwargs)


with tempfile.TemporaryDirectory(prefix='time-policy-') as tmp:
    d = Path(tmp)
    env = os.environ | {
        'LANG': 'C', 'SPARKY_STEREO_ROOT': str(d / 'engine'),
        'XDG_STATE_HOME': str(d / 'state'),
        'SPARKY_TIME_TSV': str(base / 'share/sparky-stereo-time/ntp-countries.tsv'),
        'SPARKY_TIME_POOLS': str(base / 'share/sparky-stereo-time/ntp-pools.txt'),
        'SPARKY_TIME_LANGDIR': str(base / 'share/sparky/sparky-stereo-time'),
        'SPARKY_TIME_PROBLEMS': str(base / 'lib/sparky-stereo-time/problems.py'),
        'SPARKY_STEREO_PROBLEMS_CATALOG': str(base / 'lib/systemd/catalog'),
        'SPARKY_TIME_OUT': str(d / 'sources.d/sparky-stereo.sources'),
        'SPARKY_TIME_AUTHCONF': str(d / 'auth.conf'),
    }
    cases = {
        'America/Sao_Paulo': ['server ' + h + ' iburst nts' for h in
                            ('gps.ntp.br', 'a.st1.ntp.br', 'c.st1.ntp.br', 'd.st1.ntp.br', 'e.st1.ntp.br')],
        'Europe/Berlin': ['server ptbtime' + str(i) + '.ptb.de iburst nts' for i in (1, 2, 3)],
        'Europe/Zurich': ['server ntp' + str(i) + '.metas.ch iburst' for i in (11, 12, 13)],
        'Europe/Lisbon': ['pool pt.pool.ntp.org iburst'],
        'Europe/Copenhagen': ['server time.dfm.dk iburst nts'],
        'Europe/Helsinki': ['server time.mikes.fi iburst'],
        'Asia/Calcutta': ['pool in.pool.ntp.org iburst'],
    }
    for zone, expected in cases.items():
        r = run([program, '--print', '--zone', zone], env)
        actual = [l for l in r.stdout.splitlines() if l.startswith(('server ', 'pool '))]
        check(zone + ' exact sources and order', r.returncode == 0 and actual == expected)
        (evidence / (zone.replace('/', '-') + '-print.txt')).write_text(r.stdout + r.stderr)
    for zone in ('Nowhere/Land',):
        out = Path(env['SPARKY_TIME_OUT'])
        out.parent.mkdir(exist_ok=True)
        out.write_text('server previous.example iburst\n')
        r = run([program, '--zone', zone, '--no-reload'], env)
        check(zone + ' refused without overwriting prior sources', r.returncode == 3 and out.read_text() == 'server previous.example iburst\n')
        records = list(d.rglob('sparky-stereo-time_zone.json'))
        check(zone + ' kept by the engine', bool(records))
        (evidence / (zone.replace('/', '-') + '-failure.txt')).write_text(r.stdout + r.stderr)
    for zone, cc in (('Antarctica/McMurdo', 'AQ'), ('Pacific/Guam', 'GU')):
        for mode in ('--no-reload', '--check'):
            # Seed the exact obsolete step, as the accepted previous package did.
            run(['python3', env['SPARKY_TIME_PROBLEMS'], 'record', 'zone', 'LOCAL54', cc], env)
            r = run([program, '--zone', zone, mode], env)
            notice = f"No official time service or pool.ntp.org zone was found for {cc}; the clock keeps Debian's pool, as Debian sets it up"
            check(zone + ' ' + mode + ' succeeds with one plain notice', r.returncode == 0 and (r.stdout + r.stderr).strip() == notice)
            check(zone + ' ' + mode + ' clears obsolete problem', not list(d.rglob('sparky-stereo-time_zone.json')))
            (evidence / (zone.replace('/', '-') + mode + '.txt')).write_text(r.stdout + r.stderr)
    r = run([program, '--zone', 'Nowhere/Land', '--check'], env)
    check('unknown timezone --check remains a kept fault', r.returncode == 3 and bool(list(d.rglob('sparky-stereo-time_zone.json'))))
    for lang in ('en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW'):
        words = run(['bash', '-c', 'source "$1"; printf "$LOCAL54" GU', 'bash', base / 'share/sparky/sparky-stereo-time' / lang], env).stdout
        r = run([program, '--zone', 'Pacific/Guam', '--check'], env | {'LANGUAGE': lang, 'LANG': lang + '.UTF-8'})
        (evidence / ('notice-' + lang + '.txt')).write_text(repr((r.returncode, r.stdout, r.stderr, words)))
        check(lang + ' translated no-service notice', r.returncode == 0 and (r.stdout + r.stderr).strip() == words and words)
    if helper.exists():
        conf = d / 'chrony.conf'
        vendor = Path('/usr/share/chrony/chrony.conf').read_text()
        conf.write_text(vendor)
        (d / 'ucf/cache').mkdir(parents=True)
        (d / 'debconf.conf').write_text(f'Config: config\nTemplates: templates\n\nName: config\nDriver: File\nFilename: {d}/config.dat\n\nName: templates\nDriver: File\nFilename: {d}/templates.dat\n')
        env |= {'SPARKY_TIME_CHRONY_CONF': str(conf), 'SPARKY_TIME_CONFIGURE': str(helper),
                'SPARKY_TIME_UCF_STATE': str(d / 'ucf'), 'DEBCONF_SYSTEMRC': str(d / 'debconf.conf'),
                'DEBIAN_FRONTEND': 'noninteractive'}
        r = run(['fakeroot', 'ucf', '--state-dir', d / 'ucf', '--three-way', '/usr/share/chrony/chrony.conf', conf], env)
        check('ucf baseline registered', r.returncode == 0)
        r = run(['fakeroot', helper, 'apply'], env)
        check('ucf removes Debian pool from unchanged config', r.returncode == 10 and 'pool 2.debian.pool.ntp.org iburst' not in conf.read_text())
        check('ucf records the migrated bytes', (d / 'ucf/hashfile').is_file() and str(conf) in (d / 'ucf/hashfile').read_text())
        r = run(['fakeroot', helper, 'apply'], env)
        check('configuration migration idempotent', r.returncode == 0)
        r = run(['fakeroot', helper, 'restore'], env)
        check('removal restores unedited Debian template through ucf', r.returncode == 10 and conf.read_text() == vendor)
        wrapper = d / 'configure'
        wrapper.write_text(f'#!/bin/sh\nexec fakeroot "{helper}" "$@"\n')
        wrapper.chmod(0o755)
        transition = env | {'SPARKY_TIME_CONFIGURE': str(wrapper)}
        r = run([program, '--zone', 'America/Sao_Paulo', '--no-reload'], transition)
        check('supported country before transition', r.returncode == 0 and 'pool 2.debian' not in conf.read_text())
        r = run([program, '--zone', 'Pacific/Guam', '--no-reload'], transition)
        check('no-service country restores Debian and removes previous sources and authentication', r.returncode == 0 and conf.read_text() == vendor and not Path(env['SPARKY_TIME_OUT']).exists() and not Path(env['SPARKY_TIME_AUTHCONF']).exists())
        r = run([program, '--zone', 'Pacific/Guam', '--no-reload'], transition)
        check('no-service country configuration is idempotent', r.returncode == 0 and conf.read_text() == vendor)
        personal = vendor.replace('pool 2.debian.pool.ntp.org iburst', 'server 192.0.2.7 iburst') + '\n# my own comment\n'
        conf.write_text(personal)
        out = Path(env['SPARKY_TIME_OUT'])
        out.write_text('server previous.example iburst\n')
        r = run([program, '--zone', 'Europe/Berlin', '--no-reload'], env)
        check('personal configuration preserved and reported', r.returncode == 4 and conf.read_text() == personal and 'was kept' in r.stderr)
        check('personal configuration stops new source choice', out.read_text() == 'server previous.example iburst\n')
        check('configuration problem is kept by the engine', bool(list(d.rglob('sparky-stereo-time_configuration.json'))))
        (evidence / 'personal-configuration.txt').write_text(r.stdout + r.stderr)
        run(['python3', env['SPARKY_TIME_PROBLEMS'], 'record', 'zone', 'LOCAL54', 'GU'], env)
        r = run([program, '--zone', 'Pacific/Guam', '--no-reload'], env)
        check('obsolete no-service problem clears even when personal configuration prevents restoration', r.returncode == 4 and conf.read_text() == personal and not list(d.rglob('sparky-stereo-time_zone.json')))
        r = run(['fakeroot', helper, 'restore'], env)
        check('removal also preserves personal configuration', r.returncode == 20 and conf.read_text() == personal)
        conf.unlink()
        r = run(['fakeroot', helper, 'apply'], env)
        check('deleted configuration is not recreated', r.returncode == 20 and not conf.exists())
        # Simulate chrony's own ucf step before the template-change trigger.
        conf.write_text(vendor)
        run(['fakeroot', 'ucf', '--state-dir', d / 'ucf', '--three-way', '/usr/share/chrony/chrony.conf', conf], env)
        r = run(['fakeroot', helper, 'apply'], env)
        check('template upgrade baseline', r.returncode in (0, 10))
        upgrade = d / 'vendor-upgrade'
        upgrade.write_text(vendor + '\n# new vendor revision\n')
        r = run(['fakeroot', 'ucf', '--state-dir', d / 'ucf', '--three-way', upgrade, conf], env)
        check('chrony vendor upgrade through ucf', r.returncode == 0 and conf.read_text() == upgrade.read_text())
        r = run(['fakeroot', helper, 'apply'], env | {'SPARKY_TIME_CHRONY_TEMPLATE': str(upgrade)})
        check('trigger reapplies policy after vendor upgrade', r.returncode == 10 and '# new vendor revision' in conf.read_text() and 'pool 2.debian' not in conf.read_text())
        env.pop('SPARKY_TIME_CHRONY_CONF')
    else:
        check('configuration migration helper is installed', False)

    if '--runtime' in sys.argv:
        for zone in list(cases)[:4]:
            case = d / zone.replace('/', '-')
            case.mkdir(mode=0o700)
            sources = case / 'sources.d'
            sources.mkdir()
            cfg = case / 'chrony.conf'
            vendor = Path('/usr/share/chrony/chrony.conf').read_text()
            cfg.write_text(vendor)
            liveenv = env | {'SPARKY_TIME_OUT': str(sources / 'sparky-stereo.sources'),
                             'SPARKY_TIME_AUTHCONF': str(case / 'auth.conf'),
                             'SPARKY_TIME_CHRONY_CONF': str(cfg)}
            if helper.exists():
                # Run ucf in fake-root solely for its root check; the filesystem
                # and chronyd itself remain owned by the real uid 1000.
                wrapper = case / 'configure'
                wrapper.write_text(f'#!/bin/sh\nexec fakeroot "{helper}" "$@"\n')
                wrapper.chmod(0o755)
                liveenv['SPARKY_TIME_CONFIGURE'] = str(wrapper)
                liveenv['SPARKY_TIME_UCF_STATE'] = str(case / 'ucf')
                (case / 'ucf/cache').mkdir(parents=True)
                r = run(['fakeroot', 'ucf', '--state-dir', case / 'ucf', '--three-way', '/usr/share/chrony/chrony.conf', cfg], liveenv)
                check(zone + ' runtime ucf baseline', r.returncode == 0)
            r = run([program, '--zone', zone, '--no-reload'], liveenv)
            check(zone + ' runtime generator', r.returncode == 0)
            (evidence / (case.name + '-generation.txt')).write_text(r.stdout + r.stderr)
            # Relocate only daemon state and includes into this uid's temporary
            # directory; all server/pool lines are the real generated policy.
            lines = [l for l in cfg.read_text().splitlines() if l and not l.startswith('#') and l.split()[0] in ('server', 'pool')]
            lines += [f'sourcedir {sources}', f'pidfile {case}/pid', f'bindcmdaddress {case}/chronyd.sock',
                      'port 0', 'cmdport 0', f'ntsdumpdir {case}']
            auth = case / 'auth.conf'
            if auth.exists():
                lines += [f'include {auth}']
            cfg.write_text('\n'.join(lines) + '\n')
            log = evidence / (case.name + '-chronyd.log')
            with log.open('w') as handle:
                proc = subprocess.Popen(['chronyd', '-U', '-u', 'lane', '-x', '-d', '-f', str(cfg)], stdout=handle, stderr=subprocess.STDOUT)
                try:
                    rows = []
                    observed = set()
                    expected = {x.split()[1] for x in cases[zone]}
                    for _ in range(30):
                        time.sleep(1)
                        r = run(['chronyc', '-h', case / 'chronyd.sock', '-N', '-c', 'sources'], env, timeout=10)
                        rows = [x.split(',') for x in r.stdout.splitlines() if len(x.split(',')) > 3]
                        observed = {x[2] for x in rows}
                        if expected <= observed:
                            break
                        if proc.poll() is not None:
                            break
                    (evidence / (case.name + '-sources.csv')).write_text(r.stdout + r.stderr)
                    check(zone + ' running chrony sources exactly match design', r.returncode == 0 and observed == expected)
                    print(zone, 'chronyc exit', r.returncode, 'sources', sorted(observed), flush=True)
                finally:
                    proc.terminate()
                    proc.wait(timeout=10)
print('failures:', failed)
sys.exit(bool(failed))
