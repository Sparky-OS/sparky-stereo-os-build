#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the helper's actual shell functions/worker blocks with isolated APT doubles.

Pass a package source directory to test an older revision with the same checks.
No system package manager is invoked. Run inside the package test container.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PACKAGE = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
INSTALLED = PACKAGE == Path('/usr')
SOURCE = (PACKAGE / 'bin/sparky-stereo-ffmpeg-fdk').read_text()
DEFINITIONS = SOURCE.rsplit('\ncase $MODE in', 1)[0]
WORKER = SOURCE.split('worker() {', 1)[1].split('\n}\n', 1)[0]

STUBS = r'''
logger() { :; }
apt-mark() {
    echo "mark $*" >>"$STATE/calls"
    [ "$SCENARIO" != mark-fail ]
}
apt-get() {
    echo "apt $*" >>"$STATE/calls"
    case " $* " in
    *' -s '*autoremove*)
        case "$SCENARIO" in
        autoremove-fail) echo 'fixture: autoremove failed' >&2; return 100 ;;
        needed) return 0 ;;
        esac
        printf 'Remv old-orphan [1]\nRemv tool-a [1]\nRemv unrelated [1]\n'
        ;;
    *' -s '*purge*)
        case "$SCENARIO" in
        purge-plan-fail) echo 'fixture: purge plan failed' >&2; return 100 ;;
        purge-plan-partial) echo 'Remv tool-a [1]'; return 100 ;;
        extra-removal) printf 'Remv tool-a [1]\nRemv unrelated [1]\n' ;;
        extra-purge) printf 'Purg tool-a [1]\nPurg unrelated [1]\n' ;;
        *) printf 'Purg tool-a [1]\n' ;;
        esac
        ;;
    *' -s '*build-dep*)
        case "$SCENARIO" in
        build-plan-fail) return 100 ;;
        build-removes) printf 'Inst tool-a (1 testing [amd64])\nRemv desktop [1]\n' ;;
        *) printf 'Inst tool-a (1 testing [amd64])\nInst upgrade [0] (1 testing [amd64])\n' ;;
        esac
        ;;
    *' -s '*install*)
        [ "$SCENARIO" != install-plan-fail ] || return 100
        echo 'Inst ffmpeg (1 testing [amd64])'
        ;;
    *purge*)
        [ "$SCENARIO" != purge-fail ] || { echo 'fixture: purge failed' >&2; return 100; }
        echo purged >"$STATE/purged"
        ;;
    *) echo transaction >"$STATE/transaction" ;;
    esac
}
'''


def block(start, end):
    return start + WORKER.split(start, 1)[1].split(end, 1)[0]


class FailureChecks(unittest.TestCase):
    def execute(self, scenario, body, keep=False):
        with tempfile.TemporaryDirectory(prefix='fdk-failures-', dir=os.environ.get('TMPDIR')) as tmp:
            state = Path(tmp)
            env = os.environ | {
                'SPARKY_FDK_LIBDIR': str(PACKAGE / ('lib/sparky-stereo-ffmpeg-fdk' if INSTALLED else 'lib')),
                'SPARKY_FDK_LANGDIR': str(PACKAGE / ('share/sparky/sparky-stereo-ffmpeg-fdk' if INSTALLED else 'lang')),
                'SPARKY_FDK_STATE': tmp,
                'SPARKY_FDK_LOG': str(state / 'build.log'),
                'SCENARIO': scenario, 'LANG': 'en_US.UTF-8',
            }
            setup = '''
NEW_BD=$(printf 'old-orphan\\ntool-a\\ntool-needed\\n')
A0=old-orphan
BD_INSTALLED=1
KEEP_BD=%d
VER=1
LOCALVER=1+fdk1
AUTO=1
ASSUME_YES=1
PROFILE=test
DBO_APT=
tree=/unused
''' % keep
            result = subprocess.run(['bash', '-c', DEFINITIONS + STUBS + setup + body],
                                    env=env, text=True, capture_output=True)
            files = {p.name: p.read_text() for p in state.iterdir() if p.is_file()}
            return result, files

    def test_cleanup_failures_stop_completion(self):
        finish = '\n\tremove_build_tools' + WORKER.rsplit('\n\tremove_build_tools', 1)[1]
        for scenario in ('mark-fail', 'autoremove-fail', 'purge-plan-fail',
                         'purge-plan-partial', 'extra-removal', 'extra-purge', 'purge-fail'):
            with self.subTest(scenario=scenario):
                result, files = self.execute(scenario, finish)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn('done:', result.stdout)
                self.assertNotIn('Done.', result.stdout)
                self.assertIn('cleanup failed', result.stderr)
                self.assertIn('last-cleanup-error', files)
                self.assertIn('tool-a', files['cleanup-packages'])
                self.assertNotIn('purged', files)
                if scenario != 'purge-fail':
                    self.assertFalse(any(' -s ' not in line and 'purge' in line
                                         for line in files['calls'].splitlines()))

    def test_cleanup_success_preserves_existing_and_needed_packages(self):
        result, files = self.execute('success', 'remove_build_tools')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('purged', files)
        purge = [line for line in files['calls'].splitlines() if ' -y purge ' in line]
        self.assertEqual(len(purge), 1)
        self.assertEqual(purge[0].split('purge ')[1].strip(), 'tool-a')
        self.assertNotIn('last-cleanup-error', files)

    def test_no_removable_tools_is_success(self):
        result, files = self.execute('needed', 'remove_build_tools')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('purged', files)

    def test_explicit_keep_does_not_run_apt(self):
        result, files = self.execute('success', 'remove_build_tools', keep=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('calls', files)

    def test_exit_trap_reports_cleanup_failure(self):
        for status in (0, 39):
            with self.subTest(status=status):
                result, files = self.execute('purge-plan-fail', f'trap cleanup EXIT\nexit {status}\n')
                self.assertEqual(result.returncode, status or 1, result.stderr)
                self.assertIn('last-cleanup-error', files)
                self.assertNotIn('purged', files)

    def test_build_plans_must_succeed_without_removals(self):
        prepare = block('\n\tDBO_APT=', '\n\tma=')
        for scenario in ('autoremove-fail', 'build-plan-fail', 'build-removes'):
            with self.subTest(scenario=scenario):
                result, files = self.execute(scenario, prepare)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn('transaction', files)
                self.assertTrue(result.stderr.strip())

    def test_successful_build_plan_installs_and_excludes_upgrades(self):
        prepare = block('\n\tDBO_APT=', '\n\tma=')
        result, files = self.execute('success', prepare + '\nprintf "NEW=%s\\n" "$NEW_BD"\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('transaction', files)
        self.assertIn('NEW=tool-a\n', result.stdout)

    def test_failed_install_simulation_cannot_start_install(self):
        install = block('\n\tsim=', '\n\t{')
        result, files = self.execute('install-plan-fail', install)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('transaction', files)
        self.assertTrue(result.stderr.strip())


if __name__ == '__main__':
    unittest.main(verbosity=2)
