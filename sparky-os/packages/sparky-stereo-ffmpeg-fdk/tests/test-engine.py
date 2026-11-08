#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""FDK callers against the real problems engine; only APT/dispatch are fixtures.

Run as root in a disposable container with the candidate catalogs installed.
Optional argument selects an older package tree for the red run.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

P = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
PKG = 'sparky-stereo-ffmpeg-fdk'
KEPT = 80  # check-update: failed, and the engine kept and said it
LIB = P / ('lib/' + PKG if P == Path('/usr') else 'lib')
LANG = P / ('share/sparky/' + PKG if P == Path('/usr') else 'lang')

class EngineChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.state = self.root / 'state'; self.state.mkdir()
        self.bin = self.root / 'bin'; self.bin.mkdir()
        self.env = os.environ | {'SPARKY_FDK_LIBDIR': str(LIB), 'SPARKY_FDK_LANGDIR': str(LANG),
            'SPARKY_FDK_STATE': str(self.state), 'SPARKY_STEREO_ROOT': str(self.root / 'engine'),
            'SPARKY_FDK_LOCK': str(self.root / 'lock'), 'SPARKY_FDK_LOG': str(self.root / 'log'),
            'SPARKY_FDK_HELPER_VERSION': 'H2', 'PATH': str(self.bin) + ':' + os.environ['PATH'], 'LANG': 'en_US.UTF-8', 'LANGUAGE': 'en'}
        self.source = self.root / 'Sources'
        self.source.write_text('Package: ffmpeg-dmo\nVersion: 2\nBinary: ffmpeg, libavcodec99\n\n')
        self.env['SPARKY_FDK_BIN']=str(self.bin/'worker')
        self.stub('worker', 'echo "$*" >"$SPARKY_FDK_STATE/launched"')
        self.stub('apt-get', 'printf "%s\\n" ' + repr(str(self.source)))
        self.stub('on_ac_power', 'exit 0')
        self.stub('setsid', 'echo "$*" >"$SPARKY_FDK_STATE/launched"; exit 0')
        self.stub('systemd-run', 'echo "$*" >"$SPARKY_FDK_STATE/launched"; exit 0')
        (self.state/'installed').write_text("LOCAL_BASE=1\nLOCAL_VERSION=1+fdk1\nLOCAL_USER=tester\nLOCAL_PACKAGES=ffmpeg\n")
        (self.state/'consent').write_text('accepted\n')
        self.systemd = Path('/run/systemd/system')
        self.had_systemd = self.systemd.exists()
        if self.had_systemd:
            raise RuntimeError('Use a clean container without a systemd instance')
        self.addCleanup(lambda: self.systemd.rmdir() if self.systemd.exists() else None)

    def stub(self, name, body):
        f = self.bin / name; f.write_text('#!/bin/sh\n' + body + '\n'); f.chmod(0o755)

    def run_hook(self):
        return subprocess.run(['bash', str(LIB/'check-update')], env=self.env, text=True, capture_output=True)

    def records(self):
        p = subprocess.run(['sparky-stereo-problems', 'list', '--json', PKG], env=self.env,
                           capture_output=True, text=True, check=True)
        return {r['key']: r for r in json.loads(p.stdout)}

    def keep(self, key, message='LOCAL77', args=('fixture',), details=None):
        return subprocess.run(['sparky-stereo-problems','keep','--machine','--details',json.dumps(details or {}),
                               PKG,key,message,*args], env=self.env, capture_output=True, text=True, check=True)

    def assert_failure(self, result, text=None):
        # failed, and kept and said by the engine: check-update's documented status 80, which the apt hook lets pass
        self.assertEqual(result.returncode, KEPT, result.stdout + result.stderr)
        self.assertIn('update-check', self.records())
        self.assertNotIn('last-cleanup-error', [p.name for p in self.state.iterdir()])
        self.assertTrue(result.stderr.strip())
        self.assertFalse((self.state/'launched').exists())
        if text:
            self.assertIn(text, self.records()['update-check']['text'])
            self.assertIn(text, result.stderr)

    def assert_not_kept(self, result):
        # nothing could keep it: any status but 0 and 80, so apt update fails
        self.assertNotIn(result.returncode, (0, KEPT), result.stdout + result.stderr)
        self.assertTrue(result.stderr.strip())
        self.assertFalse((self.state/'launched').exists())

    def sources(self, case):
        """An apt-get double whose indextargets lists Sources files for the case; apt-helper reads them for real."""
        other = self.root / 'Sources.other'
        other.write_text('Package: something-else\nVersion: 1\nBinary: something-else\n\n')
        self.source.write_text('Package: ffmpeg-dmo\nVersion: 2\nBinary: ffmpeg\n\n')
        if case == 'targets': body = 'exit 100'
        elif case == 'empty': body = 'exit 0'
        elif case == 'other': body = 'echo ' + repr(str(other))
        elif case == 'unreadable': body = 'echo /missing/source-index'
        elif case == 'partial': body = 'printf "%s\\n" ' + repr(str(self.source)) + ' /missing/source-index'
        elif case == 'partial-other': body = 'printf "%s\\n" ' + repr(str(other)) + ' /missing/source-index'
        else:
            self.source.write_text('Package: ffmpeg-dmo\nVersion: ' + ('invalid' if case == 'bad-version' else '2') + '\n'
                                   + ('Binary: ffmpeg\n' if case == 'bad-version' else '') + '\n')
            body = 'echo ' + repr(str(self.source))
        self.stub('apt-get', body)

    UNREADABLE = ('targets', 'unreadable', 'partial', 'partial-other', 'bad-version', 'no-binaries')
    NO_RECORD = ('empty', 'other')

    def test_missing_common_is_kept(self):
        self.env['SPARKY_FDK_LIBDIR'] = str(self.root/'missing')
        result=self.run_hook(); self.assert_failure(result)
        self.assertIn('could not load', self.records()['update-check']['text'])

    def test_repository_failures_are_not_no_update(self):
        # an index that cannot be read decides over one that lacks the record (partial-other)
        for case in self.UNREADABLE:
            with self.subTest(case=case):
                self.sources(case)
                self.assert_failure(self.run_hook(), 'update check failed')

    def test_no_source_record_is_said_as_such(self):
        for case in self.NO_RECORD:
            with self.subTest(case=case):
                self.sources(case)
                result = self.run_hook()
                self.assert_failure(result, 'has no source package ffmpeg-dmo')
                self.assertIn('sparky-stereo.sources', result.stderr)
                self.assertNotIn('update check failed', result.stderr)

    def test_failures_nothing_kept_fail_the_hook(self):
        # the engine cannot keep (its store is a file): the check's own message is still said, and the status is not 80
        broken = self.root / 'not-a-folder'
        broken.write_text('')
        self.env['SPARKY_STEREO_ROOT'] = str(broken)
        self.sources('unreadable')
        result = self.run_hook()
        self.assert_not_kept(result)
        self.assertIn('update check failed', result.stderr)
        self.sources('empty')
        result = self.run_hook()
        self.assert_not_kept(result)
        self.assertIn('has no source package ffmpeg-dmo', result.stderr)
        self.env['SPARKY_FDK_LIBDIR'] = str(self.root / 'missing')
        self.assert_not_kept(self.run_hook())

    def test_failed_clear_fails_the_hook(self):
        # a record the engine cannot remove (a folder in its place): no new version, but the clear fails
        store = self.root / 'engine/var/lib/sparky-stereo-problems'
        (store / (PKG + '_update-check.json')).mkdir(parents=True)
        self.source.write_text('Package: ffmpeg-dmo\nVersion: 1\nBinary: ffmpeg\n\n')
        self.assert_not_kept(self.run_hook())

    def run_worker(self):
        # the automatic build for real, up to the point where it reads the repository; the tools after it are doubles
        for tool in ('dpkg-buildpackage', 'fakeroot', 'runuser'):
            self.stub(tool, 'echo "$0 must not run here" >&2; exit 99')
        self.stub('id', '[ "$1 $2" = "-u tester" ] && { echo 1000; exit 0; }; exec /usr/bin/id "$@"')
        (self.root / 'log').unlink(missing_ok=True)
        result = subprocess.run(['bash', str(P / 'bin' / PKG), '--auto'], env=self.env, text=True, capture_output=True)
        log = (self.root / 'log').read_text() if (self.root / 'log').exists() else ''
        return result, log

    def assert_worker(self, text):
        result, log = self.run_worker()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr + log)
        self.assertIn(text, log)
        self.assertNotIn('update check', log)
        build = self.records()['build']
        self.assertIn(text, build['text'])
        self.assertNotIn('update check', build['text'])
        self.assertNotIn('must not run here', log)

    def test_worker_without_source_record(self):
        for case in self.NO_RECORD:
            with self.subTest(case=case):
                self.sources(case)
                self.assert_worker('has no source package ffmpeg-dmo')

    def test_worker_with_unreadable_index(self):
        for case in self.UNREADABLE:
            with self.subTest(case=case):
                self.sources(case)
                self.assert_worker('could not be read, or one of its records is invalid')

    def run_status(self):
        (self.root / 'log').write_text('')
        return subprocess.run(['bash', str(P / 'bin' / PKG), '--status'], env=self.env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def assert_status(self, text):
        result = self.run_status()
        out = result.stdout
        self.assertNotEqual(result.returncode, 0, out)
        self.assertIn(text, out)
        for line in ('Installed: FFmpeg 1+fdk1', 'Packages: ffmpeg', 'Log of the builds'):
            self.assertIn(line, out)
            self.assertLess(out.index(line), out.index(text), out)
        self.assertNotIn('update check', out)
        self.assertNotIn('LOCAL', out)

    def test_status_without_source_record(self):
        for case in self.NO_RECORD:
            with self.subTest(case=case):
                self.sources(case)
                self.assert_status('has no source package ffmpeg-dmo')

    def test_status_with_unreadable_index(self):
        for case in self.UNREADABLE:
            with self.subTest(case=case):
                self.sources(case)
                self.assert_status('could not be read, or one of its records is invalid')

    def test_both_dispatch_failures_are_kept(self):
        # A real failed exec, not just the exit code of a forked launcher.
        self.env['SPARKY_FDK_BIN']=str(self.root/'missing-worker')
        self.stub('setsid','exit 37')  # the old caller's corresponding failure
        self.assert_failure(self.run_hook())
        self.systemd.mkdir(parents=True)
        self.stub('systemd-run','echo fixture-dispatch-failure >&2; exit 37')
        self.assert_failure(self.run_hook())
        self.assertIn('systemd-run',self.records()['update-check']['text'])

    def test_success_clears_only_update_check(self):
        self.keep('update-check'); self.keep('cleanup')
        result=self.run_hook()
        self.assertEqual(result.returncode,0,result.stderr)
        for _ in range(100):
            if (self.state/'launched').exists(): break
            time.sleep(.02)
        self.assertTrue((self.state/'launched').exists())
        self.assertNotIn('update-check',self.records())
        self.assertIn('cleanup',self.records())

    def test_no_new_version_is_success_and_clears(self):
        self.keep('update-check')
        self.source.write_text('Package: ffmpeg-dmo\nVersion: 1\nBinary: ffmpeg\n\n')
        result=self.run_hook()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertNotIn('update-check',self.records())
        self.assertFalse((self.state/'launched').exists())

    def test_no_consent_or_build_stays_inactive(self):
        for name in ('consent','installed'):
            with self.subTest(name=name):
                (self.state/name).unlink(missing_ok=True)
                result=self.run_hook()
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertFalse((self.state/'launched').exists())

    def test_failed_version_under_the_same_helper_is_not_retried(self):
        # the same FFmpeg failed under this very version of the helper: the same cause would stop it again
        self.keep('build','LOCAL70',('2','/log'),{'data':{'version':'2','helper':'H2'}})
        result=self.run_hook()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('failed earlier',result.stdout)
        self.assertFalse((self.state/'launched').exists())

    def test_failed_version_under_an_older_helper_is_retried_once(self):
        # ORDER 462: a failure recorded by an older helper, or by one that recorded none (a migrated one), is tried again
        for helper in ('H1', None):
            with self.subTest(helper=helper):
                (self.state/'launched').unlink(missing_ok=True)
                data={'version':'2'}
                if helper: data['helper']=helper
                self.keep('build','LOCAL70',('2','/log'),{'data':data})
                result=self.run_hook()
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn('changed since the build',result.stdout)
                self.assertTrue((self.state/'launched').exists(), 'the rebuild was not started')

    def test_explained_build_failures(self):
        common=str(LIB/'common.sh')
        log=self.root/'build.log'
        def explain(text):
            log.write_text(text)
            return subprocess.run(['bash','-c','. "$1"; explain_build_failure "$2"',  'x', common, str(log)], env=self.env, text=True, capture_output=True)
        # the failure the station reported: the link check of Lean Code started without its archives
        r=explain('dh_builddeb\ncheck-link needs --archive-config / --scratch (or SPARKY_LC_ARCHIVE_CONFIG / SPARKY_LC_SCRATCH); see lean/archive.md\nmake[1]: *** [debian/rules:268: override_dh_builddeb] Error 1\n')
        self.assertEqual(r.returncode,0); self.assertTrue(r.stdout.startswith('LOCAL85 check-link needs --archive-config'),r.stdout)
        # another failure is told by its own last error line, never by a generic "try again"
        r=explain('configure: error: libfdk-aac not found\nmake: *** [debian/rules:195: binary-arch] Error 2\nmake[1]: Leaving directory x\n')
        self.assertEqual(r.returncode,0); self.assertTrue(r.stdout.startswith('LOCAL87 '),r.stdout); self.assertIn('Error 2',r.stdout)
        # nothing recognisable: no explanation is invented
        r=explain('all went quiet\n')
        self.assertNotEqual(r.returncode,0); self.assertEqual(r.stdout,'')

    def test_battery_and_running_build_stay_inactive(self):
        self.stub('on_ac_power','exit 1')
        result=self.run_hook()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('mains power',result.stdout)
        self.assertFalse((self.state/'launched').exists())
        self.stub('on_ac_power','exit 0')
        import fcntl
        with open(self.env['SPARKY_FDK_LOCK'],'w') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            result=self.run_hook()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((self.state/'launched').exists())

    def test_status_reads_engine(self):
        self.keep('cleanup','LOCAL75',('important-package',))
        result=subprocess.run(['bash',str(P/'bin'/PKG),'--status'],env=self.env,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('important-package',result.stdout+result.stderr)
        self.assertIn('build tools were kept',result.stdout+result.stderr)

    def test_legacy_records_migrate_without_private_store(self):
        (self.state/'last-failure').write_text('2\n')
        (self.state/'last-cleanup-error').write_text('old cleanup failure\n')
        (self.state/'cleanup-packages').write_text('tool-a\ntool-b\n')
        result=subprocess.run(['python3',str(LIB/'migrate-problems')],env=self.env,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)
        rows=self.records()
        self.assertEqual(rows['build']['data']['version'],'2')
        self.assertEqual(rows['build']['repair'],[])
        self.assertIn('--rebuild',rows['build']['text'])
        self.assertEqual(rows['cleanup']['data']['packages'],['tool-a','tool-b'])
        self.assertTrue(rows['cleanup']['data']['legacy'])
        for lang in ('en','pl','pt_BR','fr','de','ja','ko','zh_CN','zh_TW'):
            with self.subTest(lang=lang):
                self.env['LANGUAGE']=lang
                row=self.records()['cleanup']
                self.assertEqual(row['lang'],lang)
                self.assertNotIn('LOCAL82',row['text'])
                self.assertEqual(row['more'],[['LOCAL82']])
        self.env['LANGUAGE']='en'
        self.assertIn('without a saved safe plan',self.records()['cleanup']['text'])
        for name in ('last-failure','last-cleanup-error','cleanup-packages'):
            self.assertFalse((self.state/name).exists())

    def test_migration_failure_keeps_old_evidence(self):
        (self.state/'last-failure').write_text('2\n')
        self.stub('sparky-stereo-problems','exit 23')
        result=subprocess.run(['python3',str(LIB/'migrate-problems')],env=self.env,text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.state/'last-failure').read_text(),'2\n')

    def test_unsafe_cleanup_message_in_every_language(self):
        for lang in ('en','pl','pt_BR','fr','de','ja','ko','zh_CN','zh_TW'):
            with self.subTest(lang=lang):
                self.env['LANGUAGE']=lang
                self.keep('cleanup','LOCAL75',('keep-this-package',))
                row=self.records()['cleanup']
                self.assertEqual(row['lang'],lang)
                self.assertIn('keep-this-package',row['text'])
                self.assertNotIn('LOCAL75',row['text'])

if __name__=='__main__': unittest.main(verbosity=2)
