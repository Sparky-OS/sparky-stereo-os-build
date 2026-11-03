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
    state = dict(lid='b true\n', capability='s "yes"\n', status=0)
    def call(command):
        if command[0] == 'busctl':
            answer = state['lid'] if command[-1] == 'LidIsPresent' else state['capability']
            return subprocess.CompletedProcess(command, state['status'], answer, 'fixture bus failure' if state['status'] else '')
        if command[0] == 'journalctl':
            return subprocess.CompletedProcess(command, 0, 'Failed to put system to sleep: No space left on device\n', '')
        return real_call(command)
    is_dir = Path.is_dir
    def running(path):
        return True if str(path) == '/run/systemd/system' else is_dir(path)
    def records(machine=False):
        scope = '--machine' if machine else '--person'
        p = subprocess.run(['sparky-stereo-problems', 'list', scope, '--json'], text=True, capture_output=True, check=True)
        return json.loads(p.stdout)
    with patch.object(module, 'call', call), patch.object(Path, 'is_dir', running):
        assert module.session_check() == 0
        assert not records()
        state['capability'] = 's "no"\n'
        assert module.session_check() == 1 and records()
        print('PASS unavailable hibernation is shown and kept for the person')
        state['capability'] = 's "challenge"\n'
        assert module.session_check() == 0 and not records()
        state['status'] = 7
        assert module.session_check() == 1 and records()
        state['status'] = 0
        state['lid'] = 'b false\n'
        assert module.session_check() == 0 and not records()
        print('PASS command failure, repair check, and desktop non-applicability')
        state['lid'] = 'b true\n'
        (home / 'powerdevilrc').write_text('[Battery][SuspendAndShutdown]\nSleepMode=1\n[LowBattery][SuspendAndShutdown]\nSleepMode=2\n')
        state['capability'] = 's "no"\n'
        assert module.session_check() == 0 and not records()
        print('PASS no capability warning when the person selected another sleep mode')
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
