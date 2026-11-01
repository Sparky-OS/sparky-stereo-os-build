# SPDX-License-Identifier: MIT
"""ORDER 311: repo/lc-reproject.py (a published lc1 package projected again from its HR companion at a new version)
and repo/lc-successor.py (the next +lc1 source with this toolkit and no other change)."""
import gzip
import json
import lzma
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from lean import package, project

REPO = Path(__file__).resolve().parents[2] / 'repo'
ME = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
HEADER = (b'#ifndef DEMO_H\n#define DEMO_H\n/* A long comment, long enough to outweigh the pointer line the projection\n'
          b'   leaves at its place: it explains what demo() does, why it takes no argument, what it returns and\n'
          b'   which callers rely on it, over several lines, as header comments do. */\n'
          b'int demo(void); /* trailing remark about the declaration above */\n#define TWO 2 // why two\n#endif\n')
OLD_CL = (f'demo (1.0-1+lc1) UNRELEASED; urgency=medium\n\n  * Apply verified native Lean Code before compilation and qualified lc1\n'
          f'    payload assembly; retain exact authored source and HR companions.\n\n -- {ME}  Fri, 30 Oct 2026 15:41:34 -0300\n\n'
          f'demo (1.0-1) unstable; urgency=medium\n\n  * Initial.\n\n -- {ME}  Fri, 30 Oct 2026 15:00:00 -0300\n').encode()
NEW_CL = (f'demo (1.0-2+lc1) UNRELEASED; urgency=medium\n\n  * Lean Code.\n\n -- {ME}  Sat, 31 Oct 2026 20:00:00 -0300\n\n'
          f'demo (1.0-2) unstable; urgency=medium\n\n  * No-change rebuild (ORDER 311).\n\n -- {ME}  Sat, 31 Oct 2026 19:59:00 -0300\n\n'
          f'demo (1.0-1) unstable; urgency=medium\n\n  * Initial.\n\n -- {ME}  Fri, 30 Oct 2026 15:00:00 -0300\n').encode()


def gz(data):
    return subprocess.run(['gzip', '-9n'], input=data, stdout=subprocess.PIPE, check=True).stdout


def staging(root, name, control_extra='', header=True):
    (root / 'DEBIAN').mkdir(parents=True)
    (root / 'DEBIAN/control').write_text(
        f'Package: {name}\nSource: demo\nVersion: 1.0-1+lc1\nArchitecture: all\nMaintainer: {ME}\n{control_extra}'
        'Section: devel\nPriority: optional\nHomepage: https://sparkylinux.org\n'
        'Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues\nDescription: fixture\n fixture.\n')
    doc = root / f'usr/share/doc/{name}'
    doc.mkdir(parents=True)
    (doc / 'copyright').write_text('Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n')
    (doc / 'changelog.Debian.gz').write_bytes(gz(OLD_CL))
    if header:
        (root / 'usr/include').mkdir(parents=True)
        (root / 'usr/include/demo.h').write_bytes(HEADER)
    subprocess.run(['bash', str(REPO / 'provenance.sh'), '--tree', str(root)], check=True)


def forge_old_form(root, path):
    """The 0.1.15 form of a sealed tree: a #line after the removed run, the marker, manifest and md5sums made again."""
    fields = package.control(root)
    p, v, a = package.identity(fields)
    mp = root / package.manifest_path(p, a)[1:]
    obj = json.loads(mp.read_bytes())
    lines = (root / path[1:]).read_bytes().split(b'\n')
    k = next(i for i, ln in enumerate(lines) if ln.startswith(b'int demo'))
    old = b'\n'.join([ln for ln in lines[:k] if ln.strip()] + [b'#line %d' % (k + 1)] + lines[k:])
    (root / path[1:]).write_bytes(old)
    for row in obj['files']:
        if row['path'] == path:
            row.update(sha256=package.digest(old), bytes=len(old))
    obj['renderer'] = {'identity': 'lean 0.1.15 (collapse-blank,pointer)', 'sha256': '0' * 64}
    raw = package.encode(obj)
    mp.write_bytes(raw)
    package.set_fields(root / 'DEBIAN/control', {package.FIELD: f'lc1 {package.digest(raw)}'})
    sums = ''.join(sorted(f'{package.file_hash(r, "md5")}  {row["path"][1:]}\n' for r, row in package.entries(root)
                          if row['kind'] == 'file'))
    (root / 'DEBIAN/md5sums').write_text(sums)
    package.check_tree(root)
    return old


def build(tree, out):
    subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-b', str(tree), str(out)], check=True,
                   stdout=subprocess.DEVNULL)
    return out


@unittest.skipUnless(shutil.which('dpkg-deb') and shutil.which('gcc'), 'dpkg-deb and GCC required')
class Reproject(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        (self.tmp / 'old.cl').write_bytes(OLD_CL)
        (self.tmp / 'new.cl').write_bytes(NEW_CL)
        stage, hr = self.tmp / 'stage', self.tmp / 'hr'
        staging(stage, 'demo-dev')
        package.prepare(stage, hr)
        self.old_lean = forge_old_form(stage, '/usr/include/demo.h')
        self.runtime = build(stage, self.tmp / 'demo-dev_1.0-1+lc1_all.deb')
        self.hr = build(hr, self.tmp / 'demo-dev-lc-hr_1.0-1+lc1_all.deb')
        sib = self.tmp / 'sib'
        staging(sib, 'demo-cross', 'Depends: demo-dev (= 1.0-1+lc1), libc6-dev (>= 2.40)\n', header=False)
        package.prepare(sib, self.tmp / 'sib-hr')
        self.cross = build(sib, self.tmp / 'demo-cross_1.0-1+lc1_all.deb')

    def run_tool(self, *args, ok=True):
        r = subprocess.run([sys.executable, str(REPO / 'lc-reproject.py'), '--version', '1.0-2+lc1',
                            '--old-changelog', str(self.tmp / 'old.cl'), '--new-changelog', str(self.tmp / 'new.cl'),
                            '--report', str(self.tmp / 'report.json'), '--work', str(self.tmp), *map(str, args)],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode == 0, ok, r.stdout + r.stderr)
        return r

    def test_line_directives_go_and_the_authored_text_stays(self):
        out = self.tmp / 'out'
        self.run_tool('--sibling', 'demo-cross', self.runtime, self.hr, out)
        self.assertIn(b'#line', self.old_lean)
        new = out / 'demo-dev_1.0-2+lc1_all.deb'
        hr = out / 'demo-dev-lc-hr_1.0-2+lc1_all.deb'
        package_dir = self.tmp / 'x'
        subprocess.run(['dpkg-deb', '-R', str(new), str(package_dir)], check=True)
        obj = package.check_tree(package_dir)
        lean = (package_dir / 'usr/include/demo.h').read_bytes()
        self.assertNotIn(b'#line', lean)
        self.assertEqual(lean, project.project('/usr/include/demo.h', HEADER, 'demo-dev').lean)
        self.assertLess(lean.count(b'\n'), HEADER.count(b'\n'))      # 0.1.20: the comment-only lines go
        self.assertNotIn(b'\n\n', lean.split(b'\n', 1)[1])
        self.assertEqual(obj['renderer'], package.renderer())
        fields = package.control(package_dir)
        self.assertEqual(fields['version'], '1.0-2+lc1')
        self.assertEqual(fields['breaks'], 'dpkg-stereo (<< 0.1.6)')
        self.assertEqual(gzip.decompress((package_dir / 'usr/share/doc/demo-dev/changelog.Debian.gz').read_bytes()), NEW_CL)
        row = next(r for r in obj['files'] if r['path'] == '/usr/include/demo.h')
        subprocess.run(['dpkg-deb', '-x', str(hr), str(self.tmp / 'h')], check=True)
        blob = self.tmp / 'h' / package.hr_path('demo-dev', 'all', row['sha_hr'])[1:]
        self.assertEqual(lzma.decompress(blob.read_bytes()), HEADER)
        report = json.loads((self.tmp / 'report.json').read_text())
        self.assertEqual(report['stats']['tool_line_old'], 1)
        self.assertEqual(report['stats']['tool_line_new'], 0)
        self.assertEqual(report['stats']['c_files_with_tool_line_old'], 1)
        subprocess.run([sys.executable, '-m', 'lean.release', 'check-debs', str(new), str(hr)], check=True,
                       cwd=REPO.parent, stdout=subprocess.DEVNULL)

    def test_a_sibling_at_the_old_version_follows(self):
        out = self.tmp / 'out'
        self.run_tool('--sibling', 'demo-dev', self.cross, out)
        fields = next(package.stanzas(subprocess.check_output(['dpkg-deb', '-f', str(out / 'demo-cross_1.0-2+lc1_all.deb')],
                                                              text=True)))
        self.assertEqual(fields['depends'], 'demo-dev (= 1.0-2+lc1), libc6-dev (>= 2.40)')
        self.assertFalse(list(out.glob('*-lc-hr_*')))

    def test_a_relation_to_another_package_at_the_old_version_stops(self):
        self.run_tool(self.cross, self.tmp / 'out', ok=False)

    def test_the_changelog_must_be_the_old_sources(self):
        (self.tmp / 'old.cl').write_bytes(OLD_CL.replace(b'Initial', b'Other'))
        r = self.run_tool(self.runtime, self.hr, self.tmp / 'out', ok=False)
        self.assertIn('changelog', r.stderr)

    def test_the_hr_companion_is_required_and_must_match(self):
        r = self.run_tool(self.runtime, self.tmp / 'out', ok=False)
        self.assertIn('no HR companion was given', r.stderr)
        r = self.run_tool('--sibling', 'demo-dev', self.cross, self.hr, self.tmp / 'out2', ok=False)
        self.assertIn('none is expected', r.stderr)
        hr = self.tmp / 'bad-hr'
        subprocess.run(['dpkg-deb', '-R', str(self.hr), str(hr)], check=True)
        blob = next((hr / package.HR_BASE[1:]).rglob('*.xz'))
        blob.write_bytes(lzma.compress(HEADER + b'/* changed */\n'))
        mp = hr / package.manifest_path('demo-dev-lc-hr', 'all')[1:]
        obj = json.loads(mp.read_bytes())
        for row in obj['files']:
            if row['path'] == '/' + str(blob.relative_to(hr)):
                row.update(sha256=package.file_hash(blob), bytes=blob.stat().st_size)
        raw = package.encode(obj)
        mp.write_bytes(raw)
        package.set_fields(hr / 'DEBIAN/control', {package.FIELD: f'lc1 {package.digest(raw)}'})
        sums = ''.join(sorted(f'{package.file_hash(r, "md5")}  {row["path"][1:]}\n' for r, row in package.entries(hr)
                              if row['kind'] == 'file'))
        (hr / 'DEBIAN/md5sums').write_text(sums)
        r = self.run_tool(self.runtime, build(hr, self.tmp / 'bad-hr.deb'), self.tmp / 'out3', ok=False)
        self.assertIn('not the authored text', r.stderr)

    def test_a_hardlinked_payload_row_stops(self):
        stage = self.tmp / 'hl'
        subprocess.run(['dpkg-deb', '-R', str(self.runtime), str(stage)], check=True)
        mp = stage / package.manifest_path('demo-dev', 'all')[1:]
        obj = json.loads(mp.read_bytes())
        for row in obj['files']:
            if row['path'].endswith('/copyright'):
                row['reason'] = 'hardlinked payload: retained'
        raw = package.encode(obj)
        mp.write_bytes(raw)
        package.set_fields(stage / 'DEBIAN/control', {package.FIELD: f'lc1 {package.digest(raw)}'})
        sums = ''.join(sorted(f'{package.file_hash(r, "md5")}  {row["path"][1:]}\n' for r, row in package.entries(stage)
                              if row['kind'] == 'file'))
        (stage / 'DEBIAN/md5sums').write_text(sums)
        deb = build(stage, self.tmp / 'hl.deb')
        r = self.run_tool(deb, self.hr, self.tmp / 'out', ok=False)
        self.assertIn('hard-linked', r.stderr)


def plain_source(root):
    (root / 'src').mkdir(parents=True)
    (root / 'src/demo.h').write_bytes(HEADER)
    deb = root / 'debian'
    (deb / 'source').mkdir(parents=True)
    (deb / 'source/format').write_text('3.0 (quilt)\n')
    (deb / 'control').write_text(f'Source: demo\nSection: devel\nPriority: optional\nMaintainer: {ME}\n'
                                 'Build-Depends: debhelper-compat (= 13)\nStandards-Version: 4.7.4\n\n'
                                 'Package: demo-dev\nArchitecture: all\nDescription: fixture\n fixture.\n')
    (deb / 'rules').write_text('#!/usr/bin/make -f\n%:\n\tdh $@\n')
    (deb / 'rules').chmod(0o755)
    (deb / 'changelog').write_text(f'demo (1.0-1) unstable; urgency=medium\n\n  * Initial.\n\n -- {ME}  Fri, 30 Oct 2026 15:00:00 -0300\n')


@unittest.skipUnless(shutil.which('dpkg-source') and shutil.which('dch'), 'dpkg-source and dch required')
class Successor(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        os.environ.update(DEBFULLNAME='Daniel Ramos (Capitain Jack)', DEBEMAIL='Capitain_Jack@yahoo.com')

    def published(self, at_end=False):
        work = self.tmp / 'pub'
        work.mkdir()
        tree = work / 'demo-1.0'
        plain_source(tree)
        subprocess.run(['tar', '-C', str(work), '--exclude=debian', '-cJf', str(work / 'demo_1.0.orig.tar.xz'), 'demo-1.0'],
                       check=True)
        from lean import debian_prepare
        debian_prepare.prepare(tree, '1.0-1+lc1', REPO.parent, preserve_sources=[('src/demo.h', 'a generator reads it')])
        if at_end:
            control = (tree / 'debian/control').read_text()
            six = 'gcc, node-acorn, nodejs, perl, python3, python3-yaml'
            control = control.replace(f'Build-Depends: {six}, debhelper-compat (= 13)',
                                      f'Build-Depends: debhelper-compat (= 13), {six}')
            (tree / 'debian/control').write_text(control)
        subprocess.run(['dpkg-source', '-b', 'demo-1.0'], cwd=work, check=True, stdout=subprocess.DEVNULL)
        return work / 'demo_1.0-1+lc1.dsc'

    def successor(self, dsc, ok=True):
        r = subprocess.run([sys.executable, str(REPO / 'lc-successor.py'), '--next', '1.0-2', '--item', 'No-change rebuild (ORDER 311).',
                            '--work', str(self.tmp), str(dsc), str(self.tmp / 'out')], capture_output=True, text=True)
        self.assertEqual(r.returncode == 0, ok, r.stdout + r.stderr)
        return json.loads(r.stdout.splitlines()[-1]) if ok else r

    def unpack(self, dsc):
        # the new source names the published orig tarball, which the tool leaves where it is
        orig = self.tmp / 'pub/demo_1.0.orig.tar.xz'
        if not (dsc.parent / orig.name).exists():
            os.symlink(orig, dsc.parent / orig.name)
        target = self.tmp / ('x-' + dsc.stem)
        subprocess.run(['dpkg-source', '-x', str(dsc), str(target)], check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        return target

    def test_changelog_items_wrap_at_spaces_only(self):
        """ORDER 311: textwrap broke "dpkg-stereo" after its hyphen at the end of a line; names stay whole."""
        import importlib.util
        spec = importlib.util.spec_from_file_location('lc_successor', REPO / 'lc-successor.py')
        tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(tool)
        item = ('No-change rebuild of 5.73.0+git20260320.d106f1c-1 for the Lean Code toolkit 0.1.20 of build-repo main '
                '29f2ebc: C and C++ files lose their comment-only lines, with no #line directive and no empty line where a '
                'comment was; dpkg-stereo --resolve finds a lean line\'s authored line by its content (ORDER 334).')
        def body(items):
            text = tool.entry('kcgroups', '5.73.0+git20260320.d106f1c-2', items)
            return [line for line in text.split('\n') if line.startswith(('  * ', '    '))]
        lines = body([item])
        self.assertFalse(any(line.endswith('-') for line in lines), lines)
        self.assertEqual(' '.join(line[4:] for line in lines), item)
        self.assertTrue(all(len(line) <= 79 for line in lines))
        long = '/usr/share/doc/' + 'x' * 90
        self.assertIn('    ' + long, body(['see ' + long]))

    def test_the_next_source_differs_only_in_its_changelog(self):
        report = self.successor(self.published())
        self.assertEqual(report['new'], '1.0-2+lc1')
        self.assertEqual(report['changed'], ['debian/changelog'])
        self.assertEqual(report['toolkit_files_changed'], 0)
        self.assertEqual(report['preserve_patterns'], 1)
        tree = self.unpack(self.tmp / 'out/demo_1.0-2+lc1.dsc')
        heads = re.findall(r'^demo \((\S+)\) (\S+);', (tree / 'debian/changelog').read_text(), re.M)
        self.assertEqual(heads, [('1.0-2+lc1', 'UNRELEASED'), ('1.0-2', 'unstable'), ('1.0-1', 'unstable')])
        self.assertIn('ORDER 311', (tree / 'debian/changelog').read_text())
        self.assertEqual(json.loads((tree / 'debian/sparky-lean-preserve.json').read_text()), {'src/demo.h': 'a generator reads it'})
        subprocess.run([sys.executable, str(REPO / 'plain-from-lc.py'), str(tree)], check=True, stdout=subprocess.DEVNULL)
        self.assertEqual(subprocess.check_output(['dpkg-parsechangelog', '-S', 'Version'], cwd=tree, text=True).strip(), '1.0-2')

    def test_build_dependencies_at_the_end_move_to_where_debian_prepare_puts_them(self):
        report = self.successor(self.published(at_end=True))
        self.assertEqual(report['plain_from_lc'], ['--build-depends-at-end'])
        self.assertEqual(report['changed'], ['debian/changelog', 'debian/control'])
        tree = self.unpack(self.tmp / 'out/demo_1.0-2+lc1.dsc')
        self.assertIn('Build-Depends: gcc, node-acorn, nodejs, perl, python3, python3-yaml, debhelper-compat (= 13)\n',
                      (tree / 'debian/control').read_text())

    def recipe(self, extend=True):
        recipe = self.tmp / 'recipe/debian'
        plain = self.tmp / 'plain'
        plain_source(plain)
        shutil.copytree(plain / 'debian', recipe)
        (recipe / 'rules').write_text('#!/usr/bin/make -f\n%:\n\tdh $@\n\noverride_dh_auto_install:\n\ttrue\n')
        base = (recipe / 'changelog').read_text() if extend else 'demo (0.9-1) unstable; urgency=medium\n\n  * Other.\n\n -- x  Fri, 30 Oct 2026 15:00:00 -0300\n'
        (recipe / 'changelog').write_text(f'demo (1.0-2) unstable; urgency=medium\n\n  * A recipe change (ORDER 311).\n\n -- {ME}  Sat, 31 Oct 2026 20:00:00 -0300\n\n' + base)
        return recipe

    def test_a_recipe_gives_the_next_version_and_its_debian_changes(self):
        dsc = self.published()
        r = subprocess.run([sys.executable, str(REPO / 'lc-successor.py'), '--recipe', str(self.recipe()), '--work', str(self.tmp),
                            str(dsc), str(self.tmp / 'out')], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        report = json.loads(r.stdout.splitlines()[-1])
        self.assertEqual(report['new'], '1.0-2+lc1')
        self.assertEqual(report['changed'], ['debian/changelog', 'debian/rules'])
        tree = self.unpack(self.tmp / 'out/demo_1.0-2+lc1.dsc')
        self.assertIn('override_dh_auto_install', (tree / 'debian/rules').read_text())
        self.assertIn('sparky-lean-toolkit', (tree / 'debian/rules').read_text())
        self.assertTrue((tree / 'debian/sparky-lean-preserve.json').exists())

    def test_a_recipe_that_does_not_extend_the_published_changelog_stops(self):
        dsc = self.published()
        r = subprocess.run([sys.executable, str(REPO / 'lc-successor.py'), '--recipe', str(self.recipe(extend=False)),
                            '--work', str(self.tmp), str(dsc), str(self.tmp / 'out')], capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('does not extend', r.stderr)

    def test_in_place_keeps_a_shape_plain_from_lc_does_not_know(self):
        dsc = self.published(at_end=True)
        tree = self.tmp / 'pub/demo-1.0'
        control = (tree / 'debian/control').read_text()
        six = 'gcc, node-acorn, nodejs, perl, python3, python3-yaml'
        # the six inside a folded Build-Depends, as the 20 October native batch left some sources
        (tree / 'debian/control').write_text(control.replace(f'Build-Depends: debhelper-compat (= 13), {six}',
                                                             f'Build-Depends: debhelper-compat (= 13),\n               {six}'))
        (self.tmp / 'pub' / dsc.name).unlink()
        for f in (self.tmp / 'pub').glob('demo_1.0-1+lc1.debian.tar.*'):
            f.unlink()
        subprocess.run(['dpkg-source', '-b', 'demo-1.0'], cwd=self.tmp / 'pub', check=True, stdout=subprocess.DEVNULL)
        r = subprocess.run([sys.executable, str(REPO / 'lc-successor.py'), '--next', '1.0-2', '--item', 'x', '--work', str(self.tmp),
                            str(dsc), str(self.tmp / 'out0')], capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        r = subprocess.run([sys.executable, str(REPO / 'lc-successor.py'), '--in-place', '--next', '1.0-2', '--item',
                            'No-change rebuild (ORDER 311).', '--work', str(self.tmp), str(dsc), str(self.tmp / 'out')],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        report = json.loads(r.stdout.splitlines()[-1])
        self.assertEqual((report['new'], report['changed'], report['toolkit_files_changed']), ('1.0-2+lc1', ['debian/changelog'], 0))
        new = self.unpack(self.tmp / 'out/demo_1.0-2+lc1.dsc')
        heads = re.findall(r'^demo \((\S+)\) (\S+);', (new / 'debian/changelog').read_text(), re.M)
        self.assertEqual(heads, [('1.0-2+lc1', 'UNRELEASED'), ('1.0-2', 'unstable'), ('1.0-1+lc1', 'UNRELEASED'), ('1.0-1', 'unstable')])
        self.assertEqual((new / 'debian/control').read_text(), (tree / 'debian/control').read_text())

    def test_a_version_that_does_not_advance_stops(self):
        dsc = self.published()
        r = subprocess.run([sys.executable, str(REPO / 'lc-successor.py'), '--next', '1.0-1', '--item', 'x',
                            '--work', str(self.tmp), str(dsc), str(self.tmp / 'out')], capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('does not advance', r.stderr)


if __name__ == '__main__':
    unittest.main()
