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
import time
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
# Debian's /etc/gprofng.rc in miniature (no qualified adapter reads it) and two settings that do have one
TOOLS_RC = '# gprofng-style settings; this explanation is for people.\n' * 3 + 'scc all\ndcc all:src\n'
TOOLS_SYSCTL = '# A setting that moved with the tools; the kernel reads only the line below.\n' * 4 + 'vm.swappiness = 10\n'
TOOLS_UNIT = UNIT.replace('lc-demo', 'lc-tools')
TOOLS_FILES = {'/etc/lc-tools.rc': TOOLS_RC, '/etc/sysctl.d/90-lc-tools.conf': TOOLS_SYSCTL,
               '/etc/systemd/system/lc-tools.service': TOOLS_UNIT}


def synthetic_records(P, records, c_files, per_package=45):
    """dpkg-stereo records of a big install, written as its tables: `records` rows in packages of
    `per_package` files, the first `c_files` of them C headers (their files absent: restore drops those
    records). Returns the C paths."""
    rows, c = {}, []
    for i in range(records):
        pkg = f'syn-{i // per_package:05d}'
        if i < c_files:
            path = f'/usr/include/{pkg}/f{i}.h'
            c.append(path)
            handler, variant = 'c', 'c'
        else:
            path = f'/usr/share/{pkg}/f{i}.py'
            handler, variant = 'python', ''
        rows.setdefault(pkg, {})[path] = dict(path=path, package=pkg, version='1', conffile='0', sha_orig='0' * 64,
                                              md5_orig='', sha_lean='1' * 64, handler=handler, variant=variant,
                                              bytes_orig=100, bytes_lean=90)
    d = P.state('records')
    os.makedirs(d, exist_ok=True)
    for pkg, table in rows.items():
        client.write_table(os.path.join(d, pkg + '.tsv'), client.FILE_COLS, table)
    return c


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

    def system(self, name='system'):
        root = self.base / name
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

    def test_preserved_payload_stays_as_authored_with_its_reason(self):
        root = self.stage()
        script = (root / 'usr/bin/lc-demo').read_bytes()
        out = self.base / 'preserved-out'
        release.build_tree(root, out, {'/usr/bin/lc-*': 'the vendor licence asks for unmodified files'})
        self.assertEqual((root / 'usr/bin/lc-demo').read_bytes(), script)
        obj = package.check_tree(root)
        rows = {r['path']: r for r in obj['files']}
        self.assertEqual(rows['/usr/bin/lc-demo']['status'], 'left')
        self.assertEqual(rows['/usr/bin/lc-demo']['reason'],
                         package.PRESERVED + 'the vendor licence asks for unmodified files')
        self.assertEqual(rows['/usr/bin/lc-demo']['sha256'], hashlib.sha256(script).hexdigest())
        self.assertEqual(rows['/usr/bin/lc-demo-link']['kind'], 'symlink')
        self.assertEqual(rows['/etc/systemd/system/lc-demo.service']['status'], 'projected')
        self.assertEqual(len(release.check_debs(sorted(out.glob('*.deb')))), 2)

    def test_preservation_plan_must_name_payload_files_with_reasons(self):
        for plan in ({'/usr/bin/nothing-here': 'stale'}, {'usr/bin/lc-demo': 'relative'},
                     {'/usr/bin/lc-demo': ' '}, {'/usr/../etc/x': 'escape'}, ['/usr/bin/lc-demo']):
            root = self.stage(package_name='lc-plan-' + str(abs(hash(str(plan))) % 10000))
            with self.assertRaises(package.Invalid):
                package.prepare(root, self.base / ('hr-' + root.name), preserve=plan)
            self.assertNotIn(package.FIELD.lower(), package.control(root))

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
        self.assertEqual(client.conffiles(P)['lc-demo']['/etc/systemd/system/lc-demo.service'],
                         hashlib.md5(conf.read_bytes()).hexdigest())
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

    def test_c_header_hr_companion_restores_the_authored_bytes_and_resolves(self):
        """ORDER 334: an lc1 build of a C header in the 0.1.20 form; its HR companion holds the authored bytes,
        and dpkg-stereo --resolve reads them to find a lean line's authored line by content."""
        import lzma
        tree = self.stage()
        (tree / self.C_PATH[1:]).parent.mkdir(parents=True, exist_ok=True)
        (tree / self.C_PATH[1:]).write_bytes(self.C_AUTHORED)
        out = self.base / 'out-c'
        release.build_tree(tree, out)
        lean = (tree / self.C_PATH[1:]).read_bytes()
        self.assertEqual(lean, self.new_form())
        self.assertEqual(lean.split(b'\n')[1:3], [b'int demo(void);', b'int demo_line = __LINE__;'])
        obj = package.check_tree(tree)
        row = next(r for r in obj['files'] if r['path'] == self.C_PATH)
        self.assertEqual(row['status'], 'projected')
        x = self.base / 'hr-x'
        subprocess.run(['dpkg-deb', '-x', str(out / 'lc-demo-lc-hr_1_all.deb'), str(x)], check=True)
        hr = x / package.hr_path('lc-demo', 'all', row['sha_hr'])[1:]
        self.assertEqual(lzma.decompress(hr.read_bytes()), self.C_AUTHORED)
        root, P = self.system()
        self.dpkg(root, '-i', str(out / 'lc-demo_1_all.deb'), str(out / 'lc-demo-lc-hr_1_all.deb'))
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.resolve(P, f'{self.C_PATH}:3:5'), 0)
        self.assertEqual(output.getvalue().split()[0], f'/usr/share/doc/lc-demo/hr{self.C_PATH}:4:5')

    def test_c_migration_projects_again_in_the_new_form_then_stays_idle(self):
        root, P, raw, _ = self.old_c_header()
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True)
        shutil.copy2(raw, cache)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            client.post_invoke(P, 1)
        self.assertIn('comment-only lines removed', output.getvalue())
        lean = (root / self.C_PATH[1:]).read_bytes()
        self.assertEqual(lean, self.new_form())
        self.assertEqual(lean.count(b'\n'), self.C_AUTHORED.count(b'\n') - 1)   # 2 comment lines go, the pointer comes
        rec = client.Records(P)[self.C_PATH]
        self.assertEqual((rec['sha_orig'], rec['sha_lean']), (client.sha256(self.C_AUTHORED), client.sha256(lean)))
        self.assertTrue(Path(P.state('renderer-migration-c-drop-lines-v2')).exists())
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

        def spy(P_, names, *args, **kwargs):
            tried.append(sorted(names))
            return real_restore(P_, names, *args, **kwargs)
        # the first run finds no original for demo.h, then projects other.h in the current form
        with patch.object(client, 'deb_members', return_value={}), patch.object(client, 'restore', spy):
            self.run_project(P)
        self.assertEqual(tried, [[self.C_PATH]])
        new_other = client.Records(P)[second]['sha_lean']
        self.assertNotIn(b'#line', (root / second[1:]).read_bytes())
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), old)
        self.assertIn(self.C_PATH, client.Records(P))
        self.assertFalse(Path(P.state('renderer-migration-c-drop-lines-v2')).exists())
        self.assertEqual(sorted(client.read_table(P.state('renderer-migration-c-drop-lines-v2.pending'),
                                                  ('path', 'sha_lean'))), [self.C_PATH])
        tried.clear()
        # a person's --repair-consumers tries the waiting file now (the hooks wait for a change: ORDER 315)
        with patch.object(client, 'deb_members', return_value={self.C_PATH: self.C_AUTHORED}), \
                patch.object(client, 'restore', spy), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.repair_consumers(P, force=True), 0)
        self.assertEqual(tried, [[self.C_PATH]])          # the pending file only, not the new projection
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), self.new_form())
        self.assertEqual(client.Records(P)[second]['sha_lean'], new_other)
        self.assertTrue(Path(P.state('renderer-migration-c-drop-lines-v2')).exists())
        self.assertFalse(Path(P.state('renderer-migration-c-drop-lines-v2.pending')).exists())

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
        """dpkg-stereo --resolve finds the authored line by its content in every form; --resolve-render reads
        the render's map and names an older form."""
        root, P, raw, old = self.old_c_header()
        with contextlib.redirect_stdout(io.StringIO()) as output:   # old form, no original: the line as it is
            self.assertEqual(client.resolve(P, f'{self.C_PATH}:4:5'), 0)
        self.assertIn(f"{self.C_PATH}:4:5 (this C or C++ file is in an older engine's form", output.getvalue())
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True)
        shutil.copy2(raw, cache)
        with contextlib.redirect_stdout(io.StringIO()) as output:   # old form, original at hand: by content
            self.assertEqual(client.resolve(P, f'{self.C_PATH}:4:5'), 0)
        self.assertEqual(output.getvalue().split()[0], f'/usr/share/doc/lc-demo/hr{self.C_PATH}:4:5')
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.resolve(P, f'{self.C_PATH}:4:5', by_render=True), 0)
        self.assertIn("older engine's form", output.getvalue())
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.resolve(P, f'{self.C_PATH}:2:1'), 1)     # the #line 0.1.15 wrote
        self.assertIn('#line directive', output.getvalue())
        with contextlib.redirect_stdout(io.StringIO()):
            client.repair_consumers(P)
        lean = (root / self.C_PATH[1:]).read_bytes().decode().split('\n')
        self.assertEqual(lean[2], 'int demo_line = __LINE__;')
        for by_render in (False, True):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(client.resolve(P, f'{self.C_PATH}:3:17', by_render=by_render), 0)
            self.assertEqual(output.getvalue().split()[0], f'/usr/share/doc/lc-demo/hr{self.C_PATH}:4:17')
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(client.resolve(P, f'{self.C_PATH}:2:1', by_render=by_render), 0)
            self.assertEqual(output.getvalue().split()[0], f'/usr/share/doc/lc-demo/hr{self.C_PATH}:3:1')

    def stuck_c_header(self):
        """ORDER 315: the station's case: an old-form C header whose package version no cache or archive holds,
        after the migration's first try (pending and waiting written, packages.tsv current)."""
        root, P, raw, old = self.old_c_header()
        with patch.object(client, 'deb_members', return_value={}), contextlib.redirect_stdout(io.StringIO()):
            self.run_project(P)
        marker = P.state('renderer-migration-c-drop-lines-v2')
        self.assertFalse(Path(marker).exists())
        self.assertEqual(list(client.read_table(marker + '.pending', client.PENDING_COLS)), [self.C_PATH])
        self.assertEqual([(w['package'], w['version'], w['files']) for w in
                          client.read_table(marker + '.waiting', client.WAITING_COLS).values()], [('lc-demo', '0', '1')])
        return root, P, raw, old

    def test_c_migration_waiting_version_costs_nothing_until_its_deb_comes_back(self):
        root, P, raw, old = self.stuck_c_header()
        nothing = AssertionError('a dpkg run with nothing changed read records or asked APT')
        # the hooks and the postinst: a no-op dpkg run reads the small table and stops
        with patch.object(client, 'Records', side_effect=nothing), patch.object(client, 'restore', side_effect=nothing), \
                patch.object(client, 'deb_members', side_effect=nothing), \
                patch.object(client, 'archive_versions', side_effect=nothing):
            self.assertEqual(client.repair_consumers(P), 1)
            self.assertEqual(client.migrate_c_form(P, pkgs=client.dpkg_packages(P)), 1)
        with patch.object(client, 'deb_members', side_effect=nothing), contextlib.redirect_stdout(io.StringIO()) as output:
            client.post_invoke(P, 1)
        self.assertEqual(output.getvalue(), '')
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), old)
        # its .deb arrives in APT's cache: the next hook tries it, and the migration ends
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True)
        shutil.copy2(raw, cache)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            client.post_invoke(P, 1)
        self.assertIn('comment-only lines removed', output.getvalue())
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), self.new_form())
        self.assertTrue(Path(P.state('renderer-migration-c-drop-lines-v2')).exists())
        self.assertFalse(Path(P.state('renderer-migration-c-drop-lines-v2.waiting')).exists())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.verify(P, [], True), 0)

    def test_c_migration_new_lists_ask_apt_once_and_download_nothing_they_lack(self):
        root, P, raw, old = self.stuck_c_header()
        lists = root / 'var/lib/apt/lists'
        lists.mkdir(parents=True)
        (lists / 'example_dists_testing_main_binary-amd64_Packages').write_text('Package: other\n')
        asked = []

        def madison(P_, packages):
            asked.append(sorted(packages))
            return {('lc-demo', '1')}          # the lists offer another version, not the recorded one
        nothing = AssertionError('downloaded or restored a version APT does not offer')
        with patch.object(client, 'archive_versions', madison), patch.object(client, 'restore', side_effect=nothing), \
                patch.object(client, 'deb_members', side_effect=nothing), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.repair_consumers(P), 1)
        self.assertEqual(asked, [['lc-demo']])
        self.assertEqual(output.getvalue(), '')
        # tried against these lists: the next run asks nothing
        with patch.object(client, 'archive_versions', side_effect=AssertionError('asked APT twice')):
            self.assertEqual(client.repair_consumers(P), 1)
        # lists that offer the version: tried, and with the .deb downloaded the migration ends
        os.utime(lists / 'example_dists_testing_main_binary-amd64_Packages', ns=(1, 1))
        with patch.object(client, 'archive_versions', return_value={('lc-demo', '0')}), \
                patch.object(client, 'deb_members', return_value={self.C_PATH: self.C_AUTHORED}), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.repair_consumers(P), 0)
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), self.new_form())

    def test_c_migration_drops_a_waiting_version_dpkg_replaced(self):
        root, P, raw, old = self.stuck_c_header()
        upgrade = self.stage('1')
        (upgrade / self.C_PATH[1:]).parent.mkdir(parents=True)
        (upgrade / self.C_PATH[1:]).write_bytes(self.C_AUTHORED)
        deb = self.base / 'lc-demo_1_all.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(upgrade), str(deb)], check=True, stdout=subprocess.DEVNULL)
        client.pre_invoke(P)
        self.dpkg(root, '-i', str(deb))
        with patch.object(client, 'deb_members', side_effect=AssertionError('fetched the replaced version')), \
                contextlib.redirect_stdout(io.StringIO()):
            client.post_invoke(P, 1)
        self.assertTrue(Path(P.state('renderer-migration-c-drop-lines-v2')).exists())
        rec = client.Records(P)[self.C_PATH]
        self.assertEqual(rec['version'], '1')
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), self.new_form())

    def test_verify_names_the_waiting_versions(self):
        root, P, raw, old = self.stuck_c_header()
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.verify(P, []), 0)
        lines = output.getvalue().splitlines()
        self.assertIn("PENDING   lc-demo 0: 1 C and C++ files keep an older engine's form", '\n'.join(lines))
        self.assertTrue(lines[-1].endswith('1 C and C++ files of 1 package versions waiting for their .deb (PENDING)'), lines[-1])
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.verify(P, ['lc-other']), 0)
        self.assertNotIn('PENDING', output.getvalue())

    def test_old_pending_list_is_tried_once_then_remembered_by_version(self):
        root, P, raw, old = self.stuck_c_header()
        marker = P.state('renderer-migration-c-drop-lines-v2')
        # 0.1.17's list: paths and lean hashes, no version and no .waiting
        client.write_table(marker + '.pending', ('path', 'sha_lean'), {self.C_PATH: {'path': self.C_PATH, 'sha_lean': client.sha256(old)}})
        os.unlink(marker + '.waiting')
        tried = []
        real_restore = client.restore

        def spy(P_, names, *args, **kwargs):
            tried.append(sorted(names))
            return real_restore(P_, names, *args, **kwargs)
        with patch.object(client, 'deb_members', return_value={}), patch.object(client, 'restore', spy), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(client.repair_consumers(P), 1)
            self.assertEqual(client.repair_consumers(P), 1)
        self.assertEqual(tried, [[self.C_PATH]])
        self.assertEqual(client.read_table(marker + '.pending', client.PENDING_COLS)[self.C_PATH]['version'], '0')

    def four_old_headers(self):
        extra = {f'/usr/include/lc-demo/more{i}.h': self.C_AUTHORED.replace(b'demo', b'demo%d' % i) for i in range(3)}
        root, P, raw, _ = self.old_c_header(extra)
        records = client.Records(P)
        for path, data in extra.items():       # recorded as projections whose lean bytes are what is installed
            records[path] = dict(records[self.C_PATH], path=path, sha_orig=client.sha256(data), sha_lean=client.sha256(data))
        records.save()
        return P, {self.C_PATH: self.C_AUTHORED, **extra}

    def migration_lines(self, every, seconds):
        P, originals = self.four_old_headers()
        with patch.object(client, 'PROGRESS_EVERY', every), patch.object(client, 'PROGRESS_SECONDS', seconds), \
                patch.object(client, 'deb_members', return_value=originals), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.repair_consumers(P), 0)
        return output.getvalue().splitlines()

    def test_c_migration_prints_progress_at_least_once_a_minute(self):
        # 1,000 files apart, but at least every PROGRESS_SECONDS (0 here): a line after every file
        lines = self.migration_lines(1000, 0)
        self.assertEqual([l.split(' (')[0] for l in lines if 'projected and checked' in l],
                         [f'dpkg-stereo: {n} of 4 files projected and checked' for n in (1, 2, 3)])

    def test_c_migration_progress_stays_quiet_below_both_thresholds(self):
        lines = self.migration_lines(1000, 3600)
        self.assertEqual([l for l in lines if 'projected and checked' in l], [])
        self.assertTrue(lines[-1].startswith('dpkg-stereo: C and C++ files in the new form: 4, none left in an older form'), lines)

    def test_c_migration_prints_progress_before_the_long_steps(self):
        lines = self.migration_lines(1, 3600)
        self.assertTrue(lines[0].startswith('dpkg-stereo: projecting 4 C and C++ files again (1 package versions)'), lines)
        self.assertTrue(lines[1].startswith('dpkg-stereo: putting back the originals of 4 files of 1 package versions'), lines)
        self.assertEqual(lines[2], 'dpkg-stereo: projecting and checking 4 files')
        self.assertEqual([l.split(' (')[0] for l in lines[3:6]],
                         [f'dpkg-stereo: {n} of 4 files projected and checked' for n in (1, 2, 3)])
        self.assertTrue(lines[-1].startswith('dpkg-stereo: C and C++ files in the new form: 4, none left in an older form'), lines)

    def test_migration_inside_post_invoke_still_projects_what_the_run_changed(self):
        """The migration's own projection must not mark the packages this dpkg run changed as seen
        (0.1.17 wrote every package's version to packages.tsv there, so post-invoke skipped them)."""
        root, P, raw, _ = self.old_c_header()

        def other(version):
            tree = self.base / f'lc-other-{version}'
            (tree / 'DEBIAN').mkdir(parents=True)
            (tree / 'DEBIAN/control').write_text(f'Package: lc-other\nVersion: {version}\nArchitecture: all\n'
                                                 'Maintainer: Example <dev@example.org>\nDescription: Test package\n')
            (tree / 'usr/bin').mkdir(parents=True)
            (tree / 'usr/bin/lc-other').write_text(SCRIPT.replace('hello', 'other ' + version))
            (tree / 'usr/bin/lc-other').chmod(0o755)
            deb = self.base / f'lc-other_{version}_all.deb'
            subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(tree), str(deb)], check=True, stdout=subprocess.DEVNULL)
            return deb
        self.dpkg(root, '-i', str(other('1')))
        client.write_packages(P)
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True)
        shutil.copy2(raw, cache)
        self.dpkg(root, '-i', str(other('2')))
        with contextlib.redirect_stdout(io.StringIO()):
            client.post_invoke(P, 1)
        records = client.Records(P)
        self.assertEqual((root / self.C_PATH[1:]).read_bytes(), self.new_form())
        self.assertEqual(records[self.C_PATH]['version'], '0')
        self.assertEqual({r['version'] for r in records.values() if r['package'] == 'lc-other'}, {'2'})
        self.assertTrue(any(r['package'] == 'lc-other' for r in records.values()))

    def test_dpkg_database_includes_its_journal(self):
        """Inside a dpkg run the status file is out of date until dpkg's checkpoint; a maintainer script
        sees the journal too (ORDER 315: the first install's projection missed packages configured earlier)."""
        root, P = self.system()
        probe = self.base / 'probe.py'
        probe.write_text('import importlib.machinery, importlib.util, sys\n'
                         'l = importlib.machinery.SourceFileLoader("d", sys.argv[1])\n'
                         's = importlib.util.spec_from_loader(l.name, l)\nm = importlib.util.module_from_spec(s)\n'
                         'l.exec_module(m)\nP = m.Paths(sys.argv[2])\n'
                         'print(" ".join(sorted(m.dpkg_packages(P))))\n'
                         'print(m.conffiles(P).get("lc-early", {}).get("/etc/lc-early.conf"))\n')
        seen = self.base / 'seen.txt'
        early = self.base / 'early'
        (early / 'DEBIAN').mkdir(parents=True)
        (early / 'etc').mkdir()
        (early / 'etc/lc-early.conf').write_text('# a setting\nkey=1\n')
        (early / 'DEBIAN/conffiles').write_text('/etc/lc-early.conf\n')
        (early / 'DEBIAN/control').write_text('Package: lc-early\nVersion: 1\nArchitecture: all\n'
                                              'Maintainer: Example <dev@example.org>\nDescription: configured first\n')
        late = self.base / 'late'
        (late / 'DEBIAN').mkdir(parents=True)
        (late / 'DEBIAN/control').write_text('Package: lc-late\nVersion: 1\nArchitecture: all\nDepends: lc-early\n'
                                             'Maintainer: Example <dev@example.org>\nDescription: configured second\n')
        (late / 'DEBIAN/postinst').write_text(f'#!/bin/sh\n[ "$1" = configure ] || exit 0\n'
                                              f'ls "$DPKG_ROOT/var/lib/dpkg/updates" | grep -c "^[0-9]" > {seen}.journal\n'
                                              f'{sys.executable} {probe} {BIN} "$DPKG_ROOT" > {seen}\n')
        (late / 'DEBIAN/postinst').chmod(0o755)
        debs = []
        for tree in (early, late):
            deb = self.base / (tree.name + '.deb')
            subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(tree), str(deb)], check=True, stdout=subprocess.DEVNULL)
            debs.append(str(deb))
        self.dpkg(root, '-i', *debs)
        self.assertGreater(int(Path(f'{seen}.journal').read_text()), 0)
        installed, conf = seen.read_text().splitlines()
        self.assertIn('lc-early', installed.split())
        self.assertEqual(conf, hashlib.md5(b'# a setting\nkey=1\n').hexdigest())
        # after the run, the checkpoint folded the journal into the status file: the same answer
        self.assertIn('lc-early', client.dpkg_packages(P))
        self.assertIn('lc-late', client.dpkg_packages(P))

    def test_lc1_markers_are_read_with_dpkg_journal(self):
        """lean.package.installed reads dpkg's database as dpkg-stereo does: inside a dpkg run an lc1
        package configured earlier is in the journal, not yet in the status file (ORDER 315)."""
        _, _, deb = self.build()
        root, P = self.system()
        self.dpkg(root, '-i', str(deb))
        status = (root / 'var/lib/dpkg/status').read_text()
        self.assertIn('Status: install ok installed', status)
        (root / 'var/lib/dpkg/updates').mkdir(exist_ok=True)
        (root / 'var/lib/dpkg/updates/0000').write_text(status)
        (root / 'var/lib/dpkg/status').write_text(status.replace('Status: install ok installed', 'Status: install ok unpacked'))
        self.assertIsInstance(package.installed(P)['lc-demo'], dict)
        self.assertIn('lc-demo', client.dpkg_packages(P))
        os.unlink(root / 'var/lib/dpkg/updates/0000')
        self.assertNotIn('lc-demo', package.installed(P))
        self.assertNotIn('lc-demo', client.dpkg_packages(P))

    def test_lc1_markers_follow_the_installed_states(self):
        """A marked package whose files are its version's own keeps its mark however dpkg left it: with its trigger
        pending or awaited, deconfigured, on hold (ORDER 367); unpacked, it has not settled its conffiles yet."""
        _, _, deb = self.build()
        root, P = self.system()
        self.dpkg(root, '-i', str(deb))
        path = root / 'var/lib/dpkg/status'
        status = path.read_text()
        for state, counted in (('install ok triggers-pending', True), ('install ok triggers-awaited', True),
                               ('install ok half-configured', True), ('hold ok installed', True),
                               ('install ok unpacked', False), ('install ok half-installed', False)):
            path.write_text(status.replace('Status: install ok installed', 'Status: ' + state))
            self.assertEqual('lc-demo' in package.installed(P), counted, state)
            self.assertEqual('lc-demo' in client.dpkg_packages(P), counted, state)
        path.write_text(status)

    def plain_deb(self, name, files, conffiles=(), control='', version='1'):
        """A package of another distribution (no lc1 mark), with an md5sums of every file it ships."""
        tree = self.base / f'tree-{name}-{version}'
        (tree / 'DEBIAN').mkdir(parents=True)
        sums = []
        for path, text in files.items():
            f = tree / path.lstrip('/')
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(text)
            f.chmod(0o755 if text.startswith('#!') else 0o644)
            sums.append(f'{hashlib.md5(text.encode()).hexdigest()}  {path.lstrip("/")}\n')
        (tree / 'DEBIAN/md5sums').write_text(''.join(sums))
        if conffiles:
            (tree / 'DEBIAN/conffiles').write_text(''.join(c + '\n' for c in conffiles))
        (tree / 'DEBIAN/control').write_text(f'Package: {name}\nVersion: {version}\nArchitecture: all\n{control}'
                                            'Maintainer: Example <dev@example.org>\nDescription: fixture\n')
        deb = self.base / f'{name}_{version}.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-b', str(tree), str(deb)], check=True,
                       stdout=subprocess.DEVNULL)
        return deb

    def moved_conffiles(self, owner='lc-tools', moved_from='lc-tools-common', name='system'):
        """Debian's binutils since 2.43.90 (bug #1093594): `owner` ships the conffiles, and `moved_from`, the
        package they moved from, keeps them in its conffiles as remove-on-upgrade entries, which dpkg records
        as "newconffile remove-on-upgrade" on a fresh install (binutils-common's /etc/gprofng.rc)."""
        root, P = self.system(name)
        a = self.plain_deb(owner, TOOLS_FILES, conffiles=list(TOOLS_FILES))
        b = self.plain_deb(moved_from, {'/usr/share/doc/lc-tools-common/README': 'data\n'},
                           conffiles=['remove-on-upgrade ' + path for path in TOOLS_FILES])
        self.dpkg(root, '-i', str(a), str(b))
        status = (root / 'var/lib/dpkg/status').read_text()
        for path in TOOLS_FILES:
            self.assertIn(f' {path} newconffile remove-on-upgrade\n', status)
            self.assertIn(f' {path} {hashlib.md5(TOOLS_FILES[path].encode()).hexdigest()}\n', status)
        return root, P

    def verify_output(self, P):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            rc = client.verify(P, [])
        return rc, out.getvalue()

    def test_conffiles_are_read_as_dpkg_reads_them(self):
        """lib/dpkg/fields.c (f_conffiles) reads each line from its end: remove-on-upgrade, then obsolete,
        then the hash; the path is the rest, spaces included."""
        entry = client.conffile_entry
        self.assertEqual(entry(' /etc/a.conf 0123\n'), ('/etc/a.conf', '0123', set()))
        self.assertEqual(entry(' /etc/a b.conf 0123\n'), ('/etc/a b.conf', '0123', set()))
        self.assertEqual(entry(' /etc/gone 0123 obsolete\n'), ('/etc/gone', '0123', {'obsolete'}))
        self.assertEqual(entry(' /etc/gprofng.rc newconffile remove-on-upgrade\n'),
                         ('/etc/gprofng.rc', 'newconffile', {'remove-on-upgrade'}))
        self.assertEqual(entry(' /etc/x 0123 obsolete remove-on-upgrade\n'),
                         ('/etc/x', '0123', {'obsolete', 'remove-on-upgrade'}))
        self.assertIsNone(entry(' /etc/x\n'))
        stanza = ('Package: p\nStatus: install ok installed\nArchitecture: all\nConffiles:\n /etc/a b.conf 0123\n'
                  ' /etc/gone 4567 obsolete\n /etc/gprofng.rc newconffile remove-on-upgrade\nVersion: 1\n\n')
        rec, = client._db_stanzas(io.StringIO(stanza))
        self.assertEqual(rec['Conffiles'], {'/etc/a b.conf': '0123', '/etc/gone': '4567'})
        self.assertEqual(rec['Version'], '1')
        # a path listed twice: the first entry is dpkg's (nis 4.5's /etc/default/nis on the station)
        stanza = ('Package: nis\nStatus: install ok installed\nArchitecture: all\nConffiles:\n'
                  ' /etc/default/nis 898c015bd0f4c11c721e40021ceed095\n /etc/default/nis 27b3e5f9d0c37dc01b02dbbeb5100775\n\n')
        rec, = client._db_stanzas(io.StringIO(stanza))
        self.assertEqual(rec['Conffiles'], {'/etc/default/nis': '898c015bd0f4c11c721e40021ceed095'})

    def test_a_moved_conffile_in_its_package_bytes_is_never_edited(self):
        """ORDER 325: binutils owns /etc/gprofng.rc in Debian's bytes, binutils-common records it as
        "newconffile remove-on-upgrade", and dpkg-stereo 0.1.21 took that word for the file's hash and called
        the file changed by the person. Each path is judged by the package whose file list holds it, in
        whichever order the status file lists the two."""
        for owner, moved_from in (('lc-tools', 'lc-tools-common'), ('lc-zz-tools', 'lc-aa-common')):
            with self.subTest(owner=owner, moved_from=moved_from):
                root, P = self.moved_conffiles(owner, moved_from, name='system-' + owner)
                self.run_project(P)
                left = client.Records(P, 'left')
                self.assertNotIn('/etc/lc-tools.rc', left)
                records = client.Records(P)
                for path in ('/etc/sysctl.d/90-lc-tools.conf', '/etc/systemd/system/lc-tools.service'):
                    self.assertNotIn(path, left)
                    self.assertEqual((records[path]['package'], records[path]['conffile']), (owner, '1'))
                    self.assertEqual(records[path]['md5_orig'], hashlib.md5(TOOLS_FILES[path].encode()).hexdigest())
                self.assertEqual((root / 'etc/lc-tools.rc').read_text(), TOOLS_RC)
                rc, out = self.verify_output(P)
                self.assertEqual(rc, 0, out)
                self.assertNotIn('EDITED', out)
                # the dpkg run after: pre-invoke gives dpkg its own bytes back, post-invoke projects them again
                self.assertEqual(client.pre_invoke(P), 2)
                for path, text in TOOLS_FILES.items():
                    self.assertEqual((root / path.lstrip('/')).read_text(), text)
                client.post_invoke(P, 1)
                rc, out = self.verify_output(P)
                self.assertEqual(rc, 0, out)
                self.assertNotIn('EDITED', out)

    def test_a_person_edit_of_a_moved_conffile_stays_edited(self):
        """The control: the person changes a setting in each conffile; dpkg-stereo leaves them as they made
        them and verify says EDITED, as before ORDER 325."""
        root, P = self.moved_conffiles()
        edits = {'/etc/lc-tools.rc': TOOLS_RC.replace('scc all\n', 'scc all:src\n'),
                 '/etc/sysctl.d/90-lc-tools.conf': TOOLS_SYSCTL.replace('= 10', '= 60'),
                 '/etc/systemd/system/lc-tools.service': TOOLS_UNIT.replace('ExecStart=', 'Nice=5\nExecStart=')}
        for path, text in edits.items():
            (root / path.lstrip('/')).write_text(text)
        self.run_project(P)
        left = client.Records(P, 'left')
        records = client.Records(P)
        rc, out = self.verify_output(P)
        for path, text in edits.items():
            self.assertEqual((left[path]['package'], left[path]['reason']), ('lc-tools', client.PERSON_CHANGED))
            self.assertNotIn(path, records)
            self.assertEqual((root / path.lstrip('/')).read_text(), text)
            self.assertIn(f'EDITED    {path} (changed by the person: left as they made it)\n', out)

    def test_a_conffile_listed_twice_is_judged_by_its_first_entry(self):
        """A package whose conffiles list a path twice gets two Conffiles entries: on a fresh install the
        second is "newconffile" (libcufile-13-4's /etc/ld.so.conf.d/gds-13-4.conf on the station), after an
        upgrade it keeps the old version's hash (nis's /etc/default/nis); dpkg's own entry is the first."""
        root, P = self.system()
        text = {v: '# A setting explained for people, kept in the HR copy.\n' * 3 + f'KEY={v}\n' for v in ('1', '2')}
        debs = {v: self.plain_deb('lc-dup', {'/etc/default/lc-dup': text[v]}, conffiles=['/etc/default/lc-dup'] * 2,
                                  version=v) for v in ('1', '2')}
        self.dpkg(root, '-i', str(debs['1']))
        status = (root / 'var/lib/dpkg/status').read_text()
        self.assertIn(f' /etc/default/lc-dup {hashlib.md5(text["1"].encode()).hexdigest()}\n'
                      ' /etc/default/lc-dup newconffile\n', status)
        self.run_project(P)
        self.assertNotIn('/etc/default/lc-dup', client.Records(P, 'left'))
        self.assertEqual(client.Records(P)['/etc/default/lc-dup']['conffile'], '1')
        client.pre_invoke(P)
        self.dpkg(root, '-i', str(debs['2']))
        status = (root / 'var/lib/dpkg/status').read_text()
        self.assertIn(f' /etc/default/lc-dup {hashlib.md5(text["2"].encode()).hexdigest()}\n'
                      f' /etc/default/lc-dup {hashlib.md5(text["1"].encode()).hexdigest()}\n', status)
        client.post_invoke(P, 1)
        rec = client.Records(P)['/etc/default/lc-dup']
        self.assertEqual((rec['version'], rec['md5_orig']), ('2', hashlib.md5(text['2'].encode()).hexdigest()))
        self.assertNotIn('/etc/default/lc-dup', client.Records(P, 'left'))
        rc, out = self.verify_output(P)
        self.assertEqual(rc, 0, out)
        self.assertNotIn('EDITED', out)

    def test_a_file_taken_over_through_replaces_is_judged_by_its_new_owner(self):
        """dpkg takes a replaced file out of the old package's file list and leaves its md5sums as they
        were (src/main/unpack.c); the file is the new owner's, in the new owner's bytes."""
        root, P = self.system()
        old = self.plain_deb('lc-z-old', {'/usr/bin/lc-moved': SCRIPT, '/usr/share/doc/lc-z-old/README': 'kept\n'})
        new = self.plain_deb('lc-a-new', {'/usr/bin/lc-moved': SCRIPT.replace('hello', 'moved')},
                             control='Replaces: lc-z-old\n')
        self.dpkg(root, '-i', str(old))
        self.dpkg(root, '-i', str(new))
        info = root / 'var/lib/dpkg/info'
        self.assertIn('/usr/bin/lc-moved\n', (info / 'lc-a-new.list').read_text())
        self.assertNotIn('/usr/bin/lc-moved\n', (info / 'lc-z-old.list').read_text())
        self.assertIn('usr/bin/lc-moved\n', (info / 'lc-z-old.md5sums').read_text())
        self.run_project(P)
        self.assertNotIn('/usr/bin/lc-moved', client.Records(P, 'left'))
        self.assertEqual(client.Records(P)['/usr/bin/lc-moved']['package'], 'lc-a-new')
        self.assertNotIn('A long explanatory comment', (root / 'usr/bin/lc-moved').read_text())
        rc, out = self.verify_output(P)
        self.assertEqual(rc, 0, out)

    def test_post_invoke_corrects_the_false_person_edits_of_0121_once(self):
        """An upgrade from 0.1.21: its records call moved conffiles in their package's bytes changed by the
        person (/etc/gprofng.rc on every edition with binutils). The postinst runs inside dpkg's run and
        leaves them; the post-invoke hook at the run's end checks each against its own package's hash once:
        those in their package's bytes are examined again, a person's edit stays EDITED."""
        root, P = self.moved_conffiles()
        person = '/etc/sysctl.d/90-lc-tools.conf'
        (root / person.lstrip('/')).write_text(TOOLS_SYSCTL.replace('= 10', '= 60'))
        left = client.Records(P, 'left')
        for path in TOOLS_FILES:      # the rows 0.1.21 wrote (ORDER 325's probe of the published 0.1.21)
            left[path] = {'path': path, 'package': 'lc-tools', 'handler': '', 'reason': client.PERSON_CHANGED}
        left.save()
        client.write_packages(P)
        # recorded well after dpkg wrote the lists, so post-invoke sees no package changed (never racy) and only
        # the migration can correct these rows
        rows = client.read_table(P.state(client.PKGS), client.PKG_COLS)
        for row in rows.values():
            row['written'] = str(int(row['list_mtime']) + 5)
        client.write_table(P.state(client.PKGS), client.PKG_COLS, rows)
        rc, out = self.verify_output(P)
        self.assertEqual(out.count('EDITED'), 3, out)
        with patch.dict(os.environ, {'DPKG_MAINTSCRIPT_NAME': 'postinst'}), \
                contextlib.redirect_stdout(io.StringIO()):
            client.repair_consumers(P, 1)
        self.assertFalse(os.path.exists(P.state(client.CONFFILE_MIGRATION)))
        self.assertEqual(len(client.Records(P, 'left')), 3)
        with contextlib.redirect_stdout(io.StringIO()) as said:
            client.post_invoke(P, 1)
        self.assertIn('dpkg-stereo: 2 conffiles in their package\'s own bytes were recorded as changed by the person',
                      said.getvalue())
        self.assertTrue(os.path.exists(P.state(client.CONFFILE_MIGRATION)))
        left, records = client.Records(P, 'left'), client.Records(P)
        self.assertEqual(sorted(left), [person])
        self.assertEqual(left[person]['reason'], client.PERSON_CHANGED)
        self.assertEqual(records['/etc/systemd/system/lc-tools.service']['conffile'], '1')
        self.assertNotIn('/etc/lc-tools.rc', records)
        rc, out = self.verify_output(P)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.splitlines()[0], f'EDITED    {person} (changed by the person: left as they made it)')
        self.assertEqual(out.count('EDITED'), 1, out)
        # done once: the next hooks only see the marker
        with patch.object(client, 'Records', side_effect=AssertionError('the left tables were read again')):
            self.assertEqual(client.repair_conffile_owners(P), 0)

    def test_restore_names_scale_to_the_station(self):
        """ORDER 310 measured 68.9 s for restore's filter on the station's 90,217 records with the 47,360
        C and C++ names the migration passed as a list; a set makes it linear (ORDER 315)."""
        root, P = self.system()
        names = synthetic_records(P, records=90217, c_files=47360)
        t0 = time.monotonic()
        with contextlib.redirect_stdout(io.StringIO()):
            client.restore(P, sorted(names), log=lambda m: None)    # the list 0.1.17's migration passed
        took = time.monotonic() - t0
        self.assertLess(took, 20, f'restore took {took:.1f} s')
        left = client.Records(P)
        self.assertEqual(len(left), 90217 - 47360)
        self.assertFalse(any(r['handler'] == 'c' for r in left.values()))

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
               'SPARKY_LC_SCRATCH': str(self.base / 'link-scratch'),
               # The lc1 gate is this test's subject; the AppStream catalogues have their own tests.
               'SPARKY_APPSTREAM': '0'}
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



class Status(unittest.TestCase):
    def test_status_names_the_version_as_the_lean_toolkits(self):
        """--status prints the version of the lean toolkit dpkg-stereo carries (lean/__init__.py), so it says
        "lean", not "dpkg-stereo" (ORDER 339); the renderer identity is not touched."""
        import lean
        with tempfile.TemporaryDirectory(prefix='test-lc-status-') as d:
            root = Path(d)
            (root / 'var/lib/dpkg/info').mkdir(parents=True)
            (root / 'var/lib/dpkg/status').touch()
            P = client.Paths(str(root))
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(client.status(P), 0)
        first = out.getvalue().splitlines()[0]
        self.assertTrue(first.startswith(f'lean {lean.VERSION}: 0 files projected, 0 left alone, 0 held'), first)
        self.assertFalse(first.startswith('dpkg-stereo '), first)


@unittest.skipUnless(shutil.which('git') and shutil.which('dpkg-source'), 'needs git and dpkg-source')
class SourcePackage(unittest.TestCase):
    """build-source.sh puts dpkg-stereo's recipe folder in the source package as git tracks it, so the
    __pycache__ and *.pyc that running bin/dpkg-stereo in a working checkout leaves never ship (ORDER 339)."""

    REPO = Path(__file__).resolve().parents[2]

    def tree(self, base):
        """A copy of the files build-source.sh reads, in their layout, with caches planted beside them."""
        root = base / 'checkout'
        recipe = root / 'sparky-os/packages/dpkg-stereo'
        shutil.copytree(self.REPO / 'packages/dpkg-stereo', recipe,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        (root / 'sparky-os/lean').mkdir(parents=True)
        for f in list((self.REPO / 'lean').glob('*.py')) + [self.REPO / 'lean/JvmLexer.java', self.REPO / 'lean/ZigTokens.zig']:
            shutil.copy2(f, root / 'sparky-os/lean')
        (root / 'sparky-os/repo').mkdir(parents=True)
        shutil.copy2(self.REPO / 'repo/provenance.sh', root / 'sparky-os/repo')
        return root, recipe

    def plant(self, recipe):
        planted = [recipe / 'bin/__pycache__/dpkg-stereo.cpython-313.pyc', recipe / 'test/__pycache__/x.cpython-313.pyc',
                   recipe / 'lib/stray.pyc']
        for f in planted:
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_bytes(b'\x00\x00 not source')
        return planted

    def members(self, root, out, env):
        proc = subprocess.run(['bash', str(root / 'sparky-os/packages/dpkg-stereo/build-source.sh')],
                              env={**env, 'OUT': str(out)}, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        tars = list(out.glob('dpkg-stereo_*.tar.xz'))
        self.assertEqual(len(tars), 1, tars)
        names = subprocess.run(['tar', '-tJf', str(tars[0])], capture_output=True, text=True, check=True).stdout
        top = tars[0].name[:-len('.tar.xz')].replace('_', '-', 1) + '/sparky-os/packages/dpkg-stereo/'
        return proc.stdout, {n[len(top):] for n in names.splitlines() if n.startswith(top) and not n.endswith('/')}

    def test_a_planted_pycache_stays_out_of_the_source_package(self):
        with tempfile.TemporaryDirectory(prefix='test-lc-source-') as d:
            base = Path(d)
            root, recipe = self.tree(base)
            env = {**os.environ, 'GIT_CEILING_DIRECTORIES': str(base), 'PYTHONDONTWRITEBYTECODE': '1',
                   'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_NOSYSTEM': '1'}
            subprocess.run(['git', 'init', '-q', str(root)], env=env, check=True)
            subprocess.run(['git', '-C', str(root), 'add', '-A'], env=env, check=True)
            tracked = {str(p.relative_to(recipe)) for p in recipe.rglob('*') if p.is_file()}
            self.assertIn('bin/dpkg-stereo', tracked)
            self.plant(recipe)
            (recipe / 'bin/notes.txt').write_text('an untracked file beside the recipe\n')
            said, got = self.members(root, base / 'out-git', env)
            self.assertFalse({n for n in got if '__pycache__' in n or n.endswith('.pyc')}, got)
            self.assertEqual(got, tracked)
            self.assertIn('as git tracks them', said)
            # without a git work tree (an unpacked source package): the folder, caches left out
            shutil.rmtree(root / '.git')
            said, got = self.members(root, base / 'out-plain', env)
            self.assertFalse({n for n in got if '__pycache__' in n or n.endswith('.pyc')}, got)
            self.assertLessEqual(tracked, got)
            self.assertIn('no git work tree', said)


if __name__ == '__main__':
    unittest.main()
