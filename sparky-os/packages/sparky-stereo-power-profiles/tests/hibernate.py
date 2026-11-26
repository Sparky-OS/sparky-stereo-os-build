#!/usr/bin/env python3
"""Defaults through real KConfig; capability/failure routes with the real engine.
Run in a disposable container. Kernel sleep and bus endpoints are fixtures.
"""
import importlib.machinery
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

pkg = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
helper = pkg / 'bin/sparky-stereo-hibernate-check'
with tempfile.TemporaryDirectory() as tmp:
    w = Path(tmp)
    config = w / 'edition'
    config.mkdir()
    shutil.copy2(pkg / 'share/powerdevilrc', config / 'powerdevilrc')
    home = w / 'person'
    home.mkdir()
    os.environ.update(XDG_CONFIG_HOME=str(home), XDG_CONFIG_DIRS=str(config),
                      XDG_STATE_HOME=str(w / 'person-state'), SPARKY_STEREO_ROOT=str(w / 'engine'),
                      SPARKY_STEREO_PROBLEMS_CATALOG=str(w / 'catalog') + ':/usr/lib/systemd/catalog', LANG='C.UTF-8')
    def read(profile, key, default='absent'):
        return subprocess.check_output(['kreadconfig6', '--file', 'powerdevilrc', '--group', profile,
                                        '--group', 'SuspendAndShutdown', '--key', key, '--default', default], text=True).strip()
    for profile in ('Battery', 'LowBattery'):
        assert read(profile, 'SleepMode') == '3', (profile, read(profile, 'SleepMode'))
        assert read(profile, 'LidAction') == '1'
        assert read(profile, 'InhibitLidActionWhenExternalMonitorPresent') == 'false'
    assert read('AC', 'LidAction') == '0'
    assert all(read(profile, 'PowerButtonAction') == '8' for profile in ('AC', 'Battery', 'LowBattery'))
    assert 'HibernateDelaySec=2h' in (pkg / 'share/50-sparky-hibernate.conf').read_text()
    print('PASS edition battery/lid/external-monitor/power-button defaults and two-hour native timer')
    (home / 'powerdevilrc').write_text('[Battery][SuspendAndShutdown]\nSleepMode=1\nLidAction=0\n')
    assert read('Battery', 'SleepMode') == '1' and read('Battery', 'LidAction') == '0'
    assert read('LowBattery', 'SleepMode') == '3'
    (home / 'powerdevilrc').unlink()
    print('PASS person KConfig choices override edition values')
    subprocess.run(['sparky-stereo-problems', 'catalog', 'sparky-stereo-power-profiles',
                    str(pkg / 'problems-lang'), str(w / 'catalog'), '--subject', 'LOCAL1'], check=True)
    module = importlib.machinery.SourceFileLoader('hibernate_check', str(helper)).load_module()
    real_call = module.call
    state = dict(capability='s "yes"\n', status=0)
    def call(command):
        if command[0] == 'busctl':
            return subprocess.CompletedProcess(command, state['status'], state['capability'],
                                               'fixture bus failure' if state['status'] else '')
        if command[0] == 'journalctl':
            return subprocess.CompletedProcess(command, 0, 'Failed to put system to sleep: No space left on device\n', '')
        return real_call(command)
    read_text = Path.read_text
    def read_fixture(path, *args, **kwargs):
        if str(path) == '/sys/power/state':
            return 'freeze mem disk\n'
        if str(path) == '/proc/cmdline':
            return 'quiet\n'
        return read_text(path, *args, **kwargs)
    def records(machine=False):
        scope = '--machine' if machine else '--person'
        p = subprocess.run(['sparky-stereo-problems', 'list', scope, '--json'], text=True, capture_output=True, check=True)
        return json.loads(p.stdout)
    with patch.object(module, 'call', call), patch.object(Path, 'read_text', read_fixture):
        assert module.boot_check() == 0 and not records(True)
        state['capability'] = 's "na"\n'
        assert module.boot_check() == 0 and module.boot_check() == 0
        (problem,) = records(True)
        assert problem['message'] == 'LOCAL7'
        assert problem['repair'] == [[module.REPAIR, 'hibernate']], problem
        assert problem['data']['notify'] is False, problem
        print('PASS one repairable hibernation problem on the Problems page')
        state['capability'] = 's "challenge"\n'
        assert module.boot_check() == 0 and not records(True)
        state['status'] = 7
        assert module.boot_check() == 0
        (problem,) = records(True)
        assert problem['message'] == 'LOCAL8' and not problem['repair'], problem
        state['status'] = 0
        assert module.boot_check() == 0 and not records(True)
        print('PASS the recorded system response explains a failed capability query')
        if os.geteuid() == 0:
            for operation, action in [('suspend-then-hibernate', 'suspend-after-failed-hibernate'),
                                      ('hybrid-sleep', 'suspend-after-failed-hybrid-sleep')]:
                os.environ['SYSTEMD_SLEEP_ACTION'] = action
                assert module.sleep_hook('pre', operation) == 1 and records(True)
                assert 'No space left on device' in json.dumps(records(True))
                os.environ['SYSTEMD_SLEEP_ACTION'] = 'suspend'
                assert module.sleep_hook('post', operation) == 0 and records(True)
                os.environ['SYSTEMD_SLEEP_ACTION'] = 'hibernate' if operation == 'suspend-then-hibernate' else operation
                assert module.sleep_hook('post', operation) == 0 and not records(True)
            print('PASS failed hibernate/hybrid phases kept before re-suspend; intermediate wake does not clear them')
        else:
            print('Machine-store hook cases require the companion root fixture run.')
