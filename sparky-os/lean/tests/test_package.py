"""Release proof and real dpkg upgrade tests in disposable roots; no host packages touched."""

import contextlib
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import lzma
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import package, project, release

BIN = Path(__file__).resolve().parents[2] / 'packages/dpkg-stereo/bin/dpkg-stereo'
loader = importlib.machinery.SourceFileLoader('dpkg_stereo_test', str(BIN))
spec = importlib.util.spec_from_loader(loader.name, loader)
client = importlib.util.module_from_spec(spec)
loader.exec_module(client)

SCRIPT = '#!/bin/sh\n' + '# A long explanatory comment for the developer, retained in HR.\n' * 12 + 'printf "hello\\n"\n'
UNIT = '# How to configure this service, kept in the separate documentation.\n' * 12 + '[Service]\nExecStart=/usr/bin/lc-demo\n'


class Packages(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='test-lc-')
        self.addCleanup(self.work.cleanup)
        self.base = Path(self.work.name)

    def stage(self, version='1', arch='all', package_name='lc-demo'):
        root = self.base / f'stage-{package_name}-{version}-{arch}'
        (root / 'DEBIAN').mkdir(parents=True)
        (root / 'DEBIAN/control').write_text(
            f'Package: {package_name}\nVersion: {version}\nArchitecture: {arch}\n'
            'Maintainer: Example <dev@example.org>\nDescription: Test package\n')
        script = root / 'usr/bin/lc-demo'
        script.parent.mkdir(parents=True)
        script.write_text(SCRIPT)
        script.chmod(0o755)
        unit = root / 'etc/systemd/system/lc-demo.service'
        unit.parent.mkdir(parents=True)
        unit.write_text(UNIT.replace('/usr/bin/lc-demo', '/usr/bin/lc-demo ' + version))
        (root / 'DEBIAN/conffiles').write_text('/etc/systemd/system/lc-demo.service\n')
        link = root / 'usr/bin/lc-demo-link'
        link.symlink_to('lc-demo')
        return root

    def build(self, version='1', arch='all'):
        root = self.stage(version, arch)
        out = self.base / ('out-' + version + '-' + arch)
        release.build_tree(root, out)
        return root, out, out / f'lc-demo_{version}_{arch}.deb'

    def system(self):
        root = self.base / 'system'
        (root / 'var/lib/dpkg/info').mkdir(parents=True)
        (root / 'var/lib/dpkg/status').touch()
        return root, client.Paths(str(root))

    def dpkg(self, root, *args):
        proc = subprocess.run(['dpkg', '--force-not-root', '--force-bad-path', '--force-script-chrootless',
                               '--root=' + str(root), *args], capture_output=True, text=True,
                              env={**os.environ, 'DPKG_STEREO_DISABLE': '1', 'DPKG_STEREO_NO_PROJECT': '1'})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc

    def run_project(self, P):
        with client.Lock(P), contextlib.redirect_stdout(io.StringIO()) as output:
            client.project_packages(P, [], 1)
        return output.getvalue()

    def test_provenance_accepts_a_symlink_only_package(self):
        root = self.base / 'binfmt'
        (root / 'DEBIAN').mkdir(parents=True)
        (root / 'DEBIAN/control').write_text(
            'Package: lc-links\nVersion: 1\nArchitecture: all\n'
            'Maintainer: Example <dev@example.org>\nDescription: Link-only fixture\n')
        link = root / 'usr/lib/binfmt.d/example.conf'
        link.parent.mkdir(parents=True)
        link.symlink_to('../example/binfmt.conf')
        provenance = Path(__file__).resolve().parents[2] / 'repo/provenance.sh'
        subprocess.run(['bash', str(provenance), '--tree', str(root)], check=True)
        self.assertEqual((root / 'DEBIAN/md5sums').read_bytes(), b'')
        self.assertEqual(os.readlink(link), '../example/binfmt.conf')
        self.assertEqual(package.control(root)['original-maintainer'], 'Example <dev@example.org>')
        out = self.base / 'links-out'
        release.build_tree(root, out)
        release.check_debs([out / 'lc-links_1_all.deb'])

    def test_build_runtime_and_hr_are_exact_and_separate(self):
        tree, out, deb = self.build()
        obj = package.check_tree(tree)
        self.assertEqual(subprocess.check_output([str(tree / 'usr/bin/lc-demo')]), b'hello\n')
        self.assertNotIn(b'A long explanatory', (tree / 'usr/bin/lc-demo').read_bytes())
        self.assertFalse((tree / 'usr/share/doc/lc-demo/hr').exists())
        self.assertEqual(len([r for r in obj['files'] if r['status'] == 'projected']), 2)
        checked = release.check_debs(sorted(out.glob('*.deb')))
        self.assertEqual(len(checked), 2)
        with self.assertRaises(package.Invalid):
            release.check_debs([deb])

    def test_epoch_stays_in_control_but_not_archive_filename(self):
        tree = self.stage('2:1.0+lc1')
        out = self.base / 'epoch-output'
        release.build_tree(tree, out)
        self.assertEqual(sorted(p.name for p in out.glob('*.deb')),
                         ['lc-demo-lc-hr_1.0+lc1_all.deb', 'lc-demo_1.0+lc1_all.deb'])
        for archive in out.glob('*.deb'):
            self.assertEqual(subprocess.check_output(
                ['dpkg-deb', '-f', str(archive), 'Version'], text=True).strip(), '2:1.0+lc1')
        self.assertEqual(len(release.check_debs(sorted(out.glob('*.deb')))), 2)

    def test_tamper_missing_unknown_marker_and_coverage(self):
        root = self.stage()
        obj = package.prepare(root, self.base / 'hr')
        marker = package.control(root)[package.FIELD.lower()]
        mp = root / package.manifest_path('lc-demo', 'all')[1:]
        raw = mp.read_bytes()
        for invalid in ('', 'lc2 ' + package.digest(raw), 'lc1 ' + '0' * 64):
            with self.assertRaises(package.Invalid):
                package.load(invalid, raw, 'lc-demo', '1', 'all')
        with self.assertRaises(package.Invalid):
            package.load(marker, raw, 'lc-demo', '2', 'all')
        (root / 'usr/bin/lc-demo').write_text('changed')
        with self.assertRaises(package.Invalid):
            package.check_tree(root)
        # Even an added file makes the original coverage proof stale.
        (root / 'usr/bin/new-file').write_text('new')
        with self.assertRaises(package.Invalid):
            package.check_tree(root)

    def test_failed_consumer_check_cannot_stamp(self):
        root = self.stage()
        with patch.object(project, '_verify', return_value=(False, 'test failure')):
            with self.assertRaises(package.Invalid):
                package.prepare(root, self.base / 'hr')
        self.assertNotIn(package.FIELD.lower(), package.control(root))

    def test_source_paths_cannot_escape(self):
        for path in ('../../file', '/../../file', '//etc/file', '/usr/./file', '/x\ny'):
            with self.assertRaises(package.Invalid):
                package.safe_path(path)

    def test_unknown_format_is_an_explicit_gap(self):
        root = self.stage()
        (root / 'usr/bin/unknown.xyz').write_text('// preserved until a consumer adapter exists\n')
        obj = package.prepare(root, self.base / 'hr')
        row = next(r for r in obj['files'] if r['path'].endswith('.xyz'))
        self.assertEqual(row['status'], 'left')
        self.assertIn('no qualified adapter', row['reason'])

    def test_old_renderer_provenance_remains_compatible(self):
        root = self.stage()
        obj = package.prepare(root, self.base / 'hr')
        obj['renderer'] = {'identity': 'lean 0.1.0 (historical)', 'sha256': 'a' * 64}
        raw = package.encode(obj)
        loaded = package.load('lc1 ' + package.digest(raw), raw, 'lc-demo', '1', 'all')
        self.assertEqual(loaded['renderer'], obj['renderer'])

    def test_checksums_cannot_precede_projection(self):
        root = self.stage()
        package.prepare(root, self.base / 'hr')
        (root / 'DEBIAN/md5sums').write_text('0' * 32 + '  usr/bin/lc-demo\n')
        with self.assertRaises(package.Invalid):
            package.check_tree(root)

    def test_provenance_must_precede_marker(self):
        root = self.stage()
        provenance = BIN.parents[3] / 'repo/provenance.sh'
        subprocess.run(['bash', str(provenance), '--tree', str(root)], check=True, capture_output=True)
        package.prepare(root, self.base / 'hr')
        before = package.control(root)
        result = subprocess.run(['bash', str(provenance), '--tree', str(root)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(package.control(root), before)

    def test_marked_install_skips_renderer_and_preserves_dpkg_baseline(self):
        tree, out, deb = self.build()
        root, P = self.system()
        self.dpkg(root, '-i', str(deb))
        self.assertIsInstance(package.installed(P)['lc-demo'], dict)
        with patch.object(project, 'project', side_effect=AssertionError('client rendered a marked package')):
            self.assertIn('1 lc1 packages', self.run_project(P))
        self.assertFalse(client.Records(P))
        conf = root / 'etc/systemd/system/lc-demo.service'
        self.assertEqual(client.conffiles(P)['/etc/systemd/system/lc-demo.service'], hashlib.md5(conf.read_bytes()).hexdigest())
        before = conf.read_bytes()
        client.pre_invoke(P)
        self.assertEqual(conf.read_bytes(), before)
        # A reinstall must not put HR into a configuration baseline either.
        self.dpkg(root, '-i', str(deb))
        client.post_invoke(P, 1)
        self.assertEqual(conf.read_bytes(), before)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.verify(P, [], True), 0)

    def test_edited_config_survives_upgrade_and_hr_resolves(self):
        _, out, deb = self.build()
        root, P = self.system()
        self.dpkg(root, '-i', str(deb))
        self.run_project(P)
        # Simulate the exact-version companion being in APT's cache, not installed.
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True)
        shutil.copy2(out / 'lc-demo-lc-hr_1_all.deb', cache)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.hr_copy(P, '/usr/bin/lc-demo'), 0)
            mr = (root / 'usr/bin/lc-demo').read_text()
            line = mr.splitlines().index('printf "hello\\n"') + 1
            self.assertEqual(client.resolve(P, f'/usr/bin/lc-demo:{line}'), 0)
        self.assertEqual((root / 'usr/share/doc/lc-demo/hr/usr/bin/lc-demo').read_text(), SCRIPT)
        conf = root / 'etc/systemd/system/lc-demo.service'
        edited = conf.read_text() + '# My own setting\nEnvironment=CHOICE=mine\n'
        conf.write_text(edited)
        _, _, next_deb = self.build('2')
        client.pre_invoke(P)
        self.dpkg(root, '--force-confold', '-i', str(next_deb))
        client.post_invoke(P, 1)
        self.assertEqual(conf.read_text(), edited)
        self.assertFalse(client.Records(P))

    def test_hr_fetch_retries_and_new_package_invalidates_completion(self):
        _, out, deb = self.build()
        root, P = self.system()
        self.dpkg(root, '-i', str(deb))
        self.run_project(P)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.fetch_hr(P), 1)
        self.assertFalse(Path(P.state('hr-fetched')).exists())
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True)
        shutil.copy2(out / 'lc-demo-lc-hr_1_all.deb', cache)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.fetch_hr(P), 0)
        self.assertTrue(Path(P.state('hr-fetched')).exists())
        self.assertIn('How to configure', (root / 'usr/share/doc/lc-demo/hr/etc/systemd/system/lc-demo.service').read_text())
        self.run_project(P)
        self.assertFalse(Path(P.state('hr-fetched')).exists())

    def test_transition_local_projection_to_prebuilt_and_back(self):
        original = self.stage('0')
        raw = self.base / 'lc-demo_0_all.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(original), str(raw)], check=True, stdout=subprocess.DEVNULL)
        root, P = self.system()
        self.dpkg(root, '-i', str(raw))
        self.run_project(P)
        self.assertTrue(client.Records(P))
        _, _, lean = self.build('1')
        client.pre_invoke(P)
        self.dpkg(root, '-i', str(lean))
        client.post_invoke(P, 1)
        self.assertFalse(client.Records(P))
        self.assertEqual(client.pre_invoke(P), 0)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.verify(P, [], True), 0)
        original = self.stage('2')
        raw = self.base / 'lc-demo_2_all.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(original), str(raw)], check=True, stdout=subprocess.DEVNULL)
        self.dpkg(root, '-i', str(raw))
        client.post_invoke(P, 1)
        self.assertTrue(client.Records(P))

    def old_shader(self):
        """Install a real unmarked archive and emulate the pre-0.1.10 record."""
        original = self.stage('0')
        path = '/usr/share/lc-demo/example.frag'
        shader = original / path[1:]
        shader.parent.mkdir(parents=True)
        authored = b'#version 330\n// Shader explanation\nvoid main() {}\n'
        lean = b'// HR pointer\n#version 330\n#line 3\nvoid main() {}\n'
        shader.write_bytes(authored)
        raw = self.base / 'lc-demo_0_all.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(original), str(raw)],
                       check=True, stdout=subprocess.DEVNULL)
        root, P = self.system()
        self.dpkg(root, '-i', str(raw))
        (root / path[1:]).write_bytes(lean)
        files = client.Records(P)
        files[path] = dict(path=path, package='lc-demo', version='0', conffile='0',
                          sha_orig=client.sha256(authored), md5_orig='', sha_lean=client.sha256(lean),
                          handler='c', variant='c', bytes_orig=len(authored), bytes_lean=len(lean))
        files.save()
        return root, P, path, raw, authored, lean

    def test_shader_migration_restores_cached_original_then_stays_idle(self):
        root, P, path, raw, authored, _ = self.old_shader()
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True)
        shutil.copy2(raw, cache)
        with contextlib.redirect_stdout(io.StringIO()):
            client.post_invoke(P, 1)
        self.assertEqual((root / path[1:]).read_bytes(), authored)
        self.assertNotIn(path, client.Records(P))
        with patch.object(client, 'Records', side_effect=AssertionError('migration rescanned records')):
            self.assertEqual(client.repair_consumers(P), 0)

    def test_shader_migration_retries_missing_original(self):
        root, P, path, _, authored, lean = self.old_shader()
        with patch.object(client, 'deb_members', return_value={}), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.repair_consumers(P), 1)
        self.assertEqual((root / path[1:]).read_bytes(), lean)
        self.assertIn(path, client.Records(P))
        self.assertFalse(Path(P.state('consumer-migration-glsl-v1')).exists())
        with patch.object(client, 'deb_members', return_value={path: authored}), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.repair_consumers(P), 0)
        self.assertEqual((root / path[1:]).read_bytes(), authored)

    def test_shader_migration_preserves_user_edits(self):
        root, P, path, _, _, _ = self.old_shader()
        edited = b'#version 330\n// My replacement shader\nvoid main() {}\n'
        (root / path[1:]).write_bytes(edited)
        with patch.object(client, 'deb_members', side_effect=AssertionError('downloaded for edited file')):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(client.repair_consumers(P), 0)
        self.assertEqual((root / path[1:]).read_bytes(), edited)
        self.assertNotIn(path, client.Records(P))

    C_PATH = '/usr/include/lc-demo/demo.h'
    C_AUTHORED = (b'// This header is explained here at length, for the people who read it, not GCC.\n'
                  b'// A second line of the same explanation, also removed from the lean form.\n'
                  b'int demo(void); /* trailing */\n'
                  b'int demo_line = __LINE__;\n')

    def old_c_header(self, extra=None):
        """Install a real unmarked archive and emulate the record and file lean 0.1.15 made: the pointer
        on a new first line and #line after it (the form ORDER 303 replaces)."""
        original = self.stage('0')
        files = {self.C_PATH: self.C_AUTHORED, **(extra or {})}
        for path, data in files.items():
            (original / path[1:]).parent.mkdir(parents=True, exist_ok=True)
            (original / path[1:]).write_bytes(data)
        raw = self.base / 'lc-demo_0_all.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(original), str(raw)],
                       check=True, stdout=subprocess.DEVNULL)
        root, P = self.system()
        self.dpkg(root, '-i', str(raw))
        old = (b'// Lean Code: HR in /usr/share/doc/lc-demo/hr/, repo.sparkyos.org/lean-code\n'
               b'#line 3\nint demo(void);\nint demo_line = __LINE__;\n')
        (root / self.C_PATH[1:]).write_bytes(old)
        records = client.Records(P)
        records[self.C_PATH] = dict(path=self.C_PATH, package='lc-demo', version='0', conffile='0',
                                    sha_orig=client.sha256(self.C_AUTHORED), md5_orig='', sha_lean=client.sha256(old),
                                    handler='c', variant='c', bytes_orig=len(self.C_AUTHORED), bytes_lean=len(old))
        records.save()
        return root, P, raw, old

    def new_form(self):
        r = project.project(self.C_PATH, self.C_AUTHORED, 'lc-demo')
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertNotIn(b'#line', r.lean)
        return r.lean

    def test_c_migration_projects_again_with_line_breaks_then_stays_idle(self):
        root, P, raw, _ = self.old_c_header()
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True)
        shutil.copy2(raw, cache)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            client.post_invoke(P, 1)
        self.assertIn('line breaks kept instead of #line', output.getvalue())
        lean = (root / self.C_PATH[1:]).read_bytes()
        self.assertEqual(lean, self.new_form())
        self.assertEqual(lean.count(b'\n'), self.C_AUTHORED.count(b'\n'))
        rec = client.Records(P)[self.C_PATH]
        self.assertEqual((rec['sha_orig'], rec['sha_lean']), (client.sha256(self.C_AUTHORED), client.sha256(lean)))
        self.assertTrue(Path(P.state('renderer-migration-c-line-breaks-v1')).exists())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.verify(P, [], True), 0)
        with patch.object(client, 'Records', side_effect=AssertionError('migration rescanned records')):
            self.assertEqual(client.repair_consumers(P), 0)

    def test_c_migration_retries_only_the_files_whose_original_is_missing(self):
        second = '/usr/include/lc-demo/other.h'
        authored = b'// Another explanation for people, long enough to be worth its own projection here.\nint other;\n'
        root, P, raw, old = self.old_c_header({second: authored})
        tried = []
        real_restore = client.restore

        def spy(P_, names, *args):
            tried.append(sorted(names))
            return real_restore(P_, names, *args)
        # the first run finds no original for demo.h, then projects other.h in the current form
        with patch.object(client, 'deb_members', return_value={}), patch.object(client, 'restore', spy):
            self.run_project(P)
        self.assertEqual(tried, [[self.C_PATH]])
        new_other = client.Records(P)[second]['sha_lean']
        self.assertNotIn(b'#line', (root / second[1:]).read_bytes())
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), old)
        self.assertIn(self.C_PATH, client.Records(P))
        self.assertFalse(Path(P.state('renderer-migration-c-line-breaks-v1')).exists())
        self.assertEqual(sorted(client.read_table(P.state('renderer-migration-c-line-breaks-v1.pending'),
                                                  ('path', 'sha_lean'))), [self.C_PATH])
        tried.clear()
        with patch.object(client, 'deb_members', return_value={self.C_PATH: self.C_AUTHORED}), \
                patch.object(client, 'restore', spy), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.repair_consumers(P), 0)
        self.assertEqual(tried, [[self.C_PATH]])          # the pending file only, not the new projection
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), self.new_form())
        self.assertEqual(client.Records(P)[second]['sha_lean'], new_other)
        self.assertTrue(Path(P.state('renderer-migration-c-line-breaks-v1')).exists())
        self.assertFalse(Path(P.state('renderer-migration-c-line-breaks-v1.pending')).exists())

    def test_c_migration_preserves_user_edits(self):
        root, P, _, _ = self.old_c_header()
        edited = b'int demo(void);\nint demo_line = 2; /* my own change */\n'
        (root / self.C_PATH[1:]).write_bytes(edited)
        with patch.object(client, 'deb_members', side_effect=AssertionError('downloaded for an edited file')):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(client.repair_consumers(P), 0)
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), edited)
        self.assertNotIn(self.C_PATH, client.Records(P))

    def test_c_resolve_maps_line_and_column(self):
        root, P, raw, old = self.old_c_header()
        with contextlib.redirect_stdout(io.StringIO()) as output:   # old form, no original: the line as it is
            self.assertEqual(client.resolve(P, f'{self.C_PATH}:4:5'), 0)
        self.assertIn(f'{self.C_PATH}:4:5 (C and C++ keep authored line numbers', output.getvalue())
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True)
        shutil.copy2(raw, cache)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.resolve(P, f'{self.C_PATH}:4:5'), 0)   # old form, original at hand
        self.assertIn("older renderer's form", output.getvalue())
        with contextlib.redirect_stdout(io.StringIO()):
            client.repair_consumers(P)
        lean = (root / self.C_PATH[1:]).read_bytes().decode().split('\n')
        self.assertEqual(lean[3], 'int demo_line = __LINE__;')
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.resolve(P, f'{self.C_PATH}:4:17'), 0)
        self.assertEqual(output.getvalue().split()[0], f'/usr/share/doc/lc-demo/hr{self.C_PATH}:4:17')
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.resolve(P, f'{self.C_PATH}:3:1'), 0)
        self.assertEqual(output.getvalue().split()[0], f'/usr/share/doc/lc-demo/hr{self.C_PATH}:3:1')

    def test_architecture_specific_manifests(self):
        a = package.prepare(self.stage('1', 'amd64'), self.base / 'hr-a')
        b = package.prepare(self.stage('1', 'i386'), self.base / 'hr-b')
        self.assertNotEqual(package.manifest_path(a['package'], a['architecture']),
                            package.manifest_path(b['package'], b['architecture']))

    def test_unedited_config_upgrade_has_no_prompt(self):
        _, _, first = self.build()
        root, P = self.system()
        self.dpkg(root, '-i', str(first))
        self.run_project(P)
        _, _, second = self.build('2')
        client.pre_invoke(P)
        proc = self.dpkg(root, '-i', str(second))
        self.assertNotIn('Configuration file', proc.stdout + proc.stderr)
        client.post_invoke(P, 1)
        self.assertIn('lc-demo 2', (root / 'etc/systemd/system/lc-demo.service').read_text())

    def test_bad_marker_uses_local_qualification(self):
        tree, _, deb = self.build()
        root, P = self.system()
        self.dpkg(root, '-i', str(deb))
        manifest = root / package.manifest_path('lc-demo', 'all')[1:]
        manifest.write_text('{}')
        with patch.object(project, 'project', wraps=project.project) as spy:
            self.assertIn('lc marker rejected', self.run_project(P))
            self.assertGreater(spy.call_count, 0)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.verify(P, [], False), 1)

    def test_prepare_cannot_write_through_symlink(self):
        root = self.stage()
        outside = self.base / 'outside'
        outside.mkdir()
        (root / 'usr/share').symlink_to(outside)
        with self.assertRaises(package.Invalid):
            package.prepare(root, self.base / 'hr')
        self.assertFalse(list(outside.iterdir()))

    def test_sealed_iso_changed_bytes_and_benchmark_are_rejected(self):
        # This checks the attestation, not bootability or the ISO filesystem format.
        iso = self.base / 'release.iso'
        iso.write_bytes(b'synthetic artifact')
        report = Path(str(iso) + '.lean-code-projection.tsv.xz')
        payload = b'path\tpackage\tprojected\n'
        report.write_bytes(lzma.compress(payload))
        proof = Path(str(iso) + '.lc-image.json')
        proof.write_bytes(package.encode({'format': 'lc1', 'scope': 'iso-qualified-payload',
            'renderer': package.renderer(), 'projection_sha256': package.digest(payload), 'packages_sha256': '0' * 64}))
        release.seal_iso(iso, report, proof)
        release.check_iso(iso)
        iso.write_bytes(b'changed artifact')
        with self.assertRaises(package.Invalid):
            release.check_iso(iso)
        control = self.base / 'test-nolean-control.iso'
        control.write_bytes(b'synthetic artifact')
        with self.assertRaises(package.Invalid):
            release.seal_iso(control, report, proof)

    def test_release_iso_cannot_disable_lean_pass(self):
        pack = BIN.parents[3] / 'iso-build/pack.sh'
        result = subprocess.run(['sh', str(pack), 'iso'], env={**os.environ, 'LEAN': '0', 'ISO_PURPOSE': 'release'},
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('release images require LEAN=1', result.stdout)

    def test_sync_gate_stops_before_rsync(self):
        repo = self.base / 'repo'
        dists = repo / 'dists/mashtabba'
        dists.mkdir(parents=True)
        for name in ('Release', 'Release.gpg', 'InRelease'):
            (dists / name).touch()
        pool = repo / 'pool/main/l/lc-demo'
        pool.mkdir(parents=True)
        root = self.stage()
        subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(root), str(pool / 'lc-demo_1_all.deb')],
                       check=True, stdout=subprocess.DEVNULL)
        result = subprocess.run(['bash', str(BIN.parents[3] / 'repo/sync-to-server.sh'), str(repo)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('release blocked', result.stderr)
        self.assertNotIn('dry run to', result.stdout)

    @unittest.skipUnless(shutil.which('gpg') and shutil.which('dpkg-scanpackages'), 'repository signing tools required')
    def test_publisher_checks_before_changing_signed_tree(self):
        _, out, _ = self.build()
        arm = self.stage(arch='arm64')
        release.build_tree(arm, out)
        home = self.base / 'test-gnupg'
        home.mkdir(mode=0o700)
        from lean.tests.archive_fixtures import signed_archive
        env = {'PATH': os.environ.get('PATH', '/usr/bin:/bin'), 'HOME': str(self.base), 'LC_ALL': 'C',
               'SPARKY_REPO_GNUPGHOME': str(home), 'TMPDIR': str(self.base),
               'SPARKY_LC_ARCHIVE_CONFIG': str(signed_archive(self.base / 'link-archive')),
               'SPARKY_LC_SCRATCH': str(self.base / 'link-scratch')}
        try:
            subprocess.run(['gpg', '--homedir', str(home), '--batch', '--pinentry-mode', 'loopback',
                            '--passphrase', '', '--quick-generate-key', 'LC Test <lc@example.org>',
                            'ed25519', 'sign', '1d'], check=True, capture_output=True)
            listing = subprocess.check_output(['gpg', '--homedir', str(home), '--with-colons', '--list-keys'],
                                              stderr=subprocess.DEVNULL, text=True)
            env['SPARKY_REPO_KEY'] = next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
            dest = self.base / 'published'
            publisher = BIN.parents[3] / 'repo/publish-tree.sh'
            proc = subprocess.run(['bash', str(publisher), str(out), str(dest)], env=env, capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            index = dest / 'dists/mashtabba/main/binary-arm64/Packages'
            self.assertIn('Architecture: arm64', index.read_text())
            signed = subprocess.run(['gpg', '--homedir', str(home), '--batch', '--decrypt',
                                     str(dest / 'dists/mashtabba/InRelease')],
                                    capture_output=True, text=True)
            self.assertEqual(signed.returncode, 0, signed.stderr)
            self.assertIn('Architectures: amd64 arm64 all', signed.stdout)
            self.assertIn(package.file_hash(index), signed.stdout)
            before = {str(p.relative_to(dest)): package.file_hash(p) for p in dest.rglob('*') if p.is_file()}
            # A newer unmarked archive must fail before any existing pool/index/signature changes.
            raw = self.stage('9')
            subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(raw), str(out / 'lc-demo_9_all.deb')],
                           check=True, stdout=subprocess.DEVNULL)
            proc = subprocess.run(['bash', str(publisher), str(out), str(dest)], env=env, capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn('release blocked', proc.stderr)
            after = {str(p.relative_to(dest)): package.file_hash(p) for p in dest.rglob('*') if p.is_file()}
            self.assertEqual(before, after)
            (out / 'lc-demo_9_all.deb').unlink()

            # A valid but different archive must not replace a published version.
            altered = self.base / 'altered'
            altered_root = self.stage(package_name='temporary-name')
            control = altered_root / 'DEBIAN/control'
            control.write_text(control.read_text().replace('temporary-name', 'lc-demo'))
            script = altered_root / 'usr/bin/lc-demo'
            script.write_text(SCRIPT.replace('hello', 'changed'))
            release.build_tree(altered_root, altered)
            proc = subprocess.run(['bash', str(publisher), str(altered), str(dest)],
                                  env=env, capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn('published archive is immutable', proc.stderr)
            self.assertEqual(before, {str(p.relative_to(dest)): package.file_hash(p)
                                      for p in dest.rglob('*') if p.is_file()})

            # Duplicate identities in one input set must also fail, even if the
            # old top-folder preference would silently pick just one of them.
            shutil.copytree(altered, out / 'carried')
            proc = subprocess.run(['bash', str(publisher), str(out), str(dest)],
                                  env=env, capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn('conflicting archives', proc.stderr)
            self.assertEqual(before, {str(p.relative_to(dest)): package.file_hash(p)
                                      for p in dest.rglob('*') if p.is_file()})
        finally:
            subprocess.run(['gpgconf', '--homedir', str(home), '--kill', 'gpg-agent'], capture_output=True)


if __name__ == '__main__':
    unittest.main()
