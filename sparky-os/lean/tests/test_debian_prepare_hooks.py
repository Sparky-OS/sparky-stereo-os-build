# SPDX-License-Identifier: MIT
"""ORDER 768b: lean.debian_prepare and a Debian rules file that already defines one of the toolkit's hooks.

Debian's glib2.0 has `execute_before_dh_auto_configure: cross-tools` (debian/rules:62 of 2.90.1-2). The step keeps such a
rule as it is and makes the toolkit's commands a prerequisite of it; an existing override_dh_builddeb is still refused.
Each kept hook is run through make: Debian's own commands write what they see of a C source into order.log (1 while the
comment is there, the authored source; 0 once the projection removed it), so the log is the order the commands ran in.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

TOOLKIT = Path(__file__).resolve().parents[2]
ENV = {'SOURCE_DATE_EPOCH': '1793974631', 'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)', 'DEBEMAIL': 'Capitain_Jack@yahoo.com'}
SOURCE = '/* fixture comment XYZ */\nint main(void) { return 0; } /* trailing */\n'
# what the step appends to a rules file with none of its targets, as it was before ORDER 768b, byte for byte
TODAY = """

# Distribution-only processing; authored source remains in the source archive.
execute_before_dh_auto_configure:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree project $(CURDIR)

execute_before_dh_auto_clean:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree restore $(CURDIR)
\trm -rf .sparky-lc

override_dh_builddeb:
\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance $(CURDIR)/debian/sparky-lean-toolkit/provenance.sh
"""
HEAD = '#!/usr/bin/make -f\n\n%:\n\tdh $@\n\n'
SEE = "printf '%s %s\\n' {label} \"$$(grep -c XYZ src/a.c)\" >> order.log"
GLIB = ('execute_before_dh_auto_configure: cross-tools\n\n'
        'cross-tools:\n\tsleep 1; ' + SEE.format(label='debian-prerequisite') + '\n')

tools = unittest.skipUnless(all(shutil.which(t) for t in ('dch', 'dpkg-parsechangelog', 'make', 'gcc')),
                            'Debian source tools, make and gcc required')


def tree(root, rules, packages=(('fixture', 'any'),)):
    (root / 'debian').mkdir()
    (root / 'src').mkdir()
    (root / 'src/a.c').write_text(SOURCE)
    (root / 'debian/rules').write_text(rules)
    (root / 'debian/rules').chmod(0o755)
    stanzas = ''.join(f'\nPackage: {name}\nArchitecture: {arch}\nDescription: fixture\n fixture\n' for name, arch in packages)
    (root / 'debian/control').write_text('Source: fixture\nMaintainer: Example <example@example.invalid>\n'
                                         'Build-Depends: debhelper-compat (= 13)\n' + stanzas)
    (root / 'debian/changelog').write_text('fixture (1) unstable; urgency=medium\n\n  * Fixture.\n\n'
                                           ' -- Example <example@example.invalid>  Tue, 20 Oct 2026 10:00:00 +0000\n')


def prepare(root):
    from lean.debian_prepare import prepare as step
    with mock.patch.dict(os.environ, ENV):
        step(root, '1+lc1', TOOLKIT)
    return (root / 'debian/rules').read_text()


def make(root, target, jobs=None):
    command = ['make', '-s', '-f', 'debian/rules'] + ([f'-j{jobs}'] if jobs else []) + [target]
    run = subprocess.run(command, cwd=root, capture_output=True, text=True,
                         env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
    if run.returncode:
        raise AssertionError(f'{command} exited {run.returncode}: {run.stdout}{run.stderr}')
    return run


def log(root):
    path = root / 'order.log'
    return path.read_text().splitlines() if path.exists() else []


@tools
class NoHook(unittest.TestCase):
    def test_a_rules_file_with_none_of_the_targets_gets_todays_text_byte_for_byte(self):
        for rules in (HEAD, HEAD + 'override_dh_auto_build:\n\tdh_auto_build -- V=1\n\n\n', '#!/usr/bin/make -f\n%:\n\tdh $@'):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                tree(root, rules)
                self.assertEqual(prepare(root), rules.rstrip() + TODAY)


@tools
class KeptConfigureHook(unittest.TestCase):
    def test_glib_line_prerequisite_without_recipe(self):
        for jobs in (None, 4):
            with self.subTest(jobs=jobs), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                rules = HEAD + GLIB
                tree(root, rules)
                written = prepare(root)
                self.assertTrue(written.startswith(rules.rstrip() + '\n'), 'Debian\'s rules must stay as they are')
                self.assertEqual(written.count('execute_before_dh_auto_configure: cross-tools\n'), 1)
                make(root, 'execute_before_dh_auto_configure', jobs)
                # Debian's prerequisite saw the authored source; the projection ran after it
                self.assertEqual(log(root), ['debian-prerequisite 1'])
                self.assertNotIn('XYZ', (root / 'src/a.c').read_text())
                self.assertTrue((root / '.sparky-lc/source.json').is_file())

    def test_hook_with_a_recipe_runs_after_the_projection(self):
        for jobs in (None, 4):
            with self.subTest(jobs=jobs), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                rules = (HEAD + 'execute_before_dh_auto_configure: cross-tools\n\t' + SEE.format(label='debian-recipe') + '\n\n'
                         'cross-tools:\n\tsleep 1; ' + SEE.format(label='debian-prerequisite') + '\n')
                tree(root, rules)
                written = prepare(root)
                self.assertTrue(written.startswith(rules.rstrip() + '\n'))
                make(root, 'execute_before_dh_auto_configure', jobs)
                self.assertEqual(log(root), ['debian-prerequisite 1', 'debian-recipe 0'])

    def test_hook_with_a_recipe_and_no_prerequisite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rules = HEAD + 'execute_before_dh_auto_configure:\n\t' + SEE.format(label='debian-recipe') + '\n'
            tree(root, rules)
            prepare(root)
            make(root, 'execute_before_dh_auto_configure')
            self.assertEqual(log(root), ['debian-recipe 0'])

    def test_arch_form_keeps_dh_running_debians_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rules = HEAD + GLIB.replace('execute_before_dh_auto_configure:', 'execute_before_dh_auto_configure-arch:')
            tree(root, rules, packages=(('fixture', 'any'), ('fixture-data', 'all')))
            written = prepare(root)
            self.assertTrue(written.startswith(rules.rstrip() + '\n'))
            # dh runs a plain hook target for every package and then never the -arch or -indep form, so the step adds
            # no plain target here; the -indep form Debian lacks gets the toolkit's prerequisite alone
            self.assertNotRegex(written, re.compile(r'^execute_before_dh_auto_configure\s*:', re.M))
            self.assertRegex(written, re.compile(r'^execute_before_dh_auto_configure-indep\s*:', re.M))
            make(root, 'execute_before_dh_auto_configure-arch')
            self.assertEqual(log(root), ['debian-prerequisite 1'])
            self.assertNotIn('XYZ', (root / 'src/a.c').read_text())
            # a full build runs both forms: the second projection finds its record and leaves the tree as it is
            lean = (root / 'src/a.c').read_bytes()
            make(root, 'execute_before_dh_auto_configure-indep')
            self.assertEqual((root / 'src/a.c').read_bytes(), lean)
            if shutil.which('dh'):
                plan = subprocess.run(['dh', 'build', '--no-act'], cwd=root, capture_output=True, text=True)
                self.assertEqual(plan.returncode, 0, plan.stderr)
                self.assertIn('debian/rules execute_before_dh_auto_configure-arch', plan.stdout)
                self.assertIn('debian/rules execute_before_dh_auto_configure-indep', plan.stdout)


@tools
class KeptCleanHook(unittest.TestCase):
    def test_restore_runs_after_debians_prerequisite_and_before_its_recipe(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rules = (HEAD + 'execute_before_dh_auto_clean: debian-clean\n\t' + SEE.format(label='debian-clean-recipe') + '\n\n'
                     'debian-clean:\n\t' + SEE.format(label='debian-clean-prerequisite') + '\n')
            tree(root, rules)
            written = prepare(root)
            self.assertTrue(written.startswith(rules.rstrip() + '\n'))
            make(root, 'execute_before_dh_auto_configure')
            self.assertNotIn('XYZ', (root / 'src/a.c').read_text())
            make(root, 'execute_before_dh_auto_clean', 4)
            self.assertEqual(log(root), ['debian-clean-prerequisite 0', 'debian-clean-recipe 1'])
            self.assertEqual((root / 'src/a.c').read_text(), SOURCE)
            self.assertFalse((root / '.sparky-lc').exists())


@tools
class StillRefused(unittest.TestCase):
    def test_existing_override_dh_builddeb_names_file_and_line(self):
        for form in ('override_dh_builddeb:', 'override_dh_builddeb-arch:'):
            with self.subTest(form=form), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                rules = HEAD + GLIB + '\n' + form + '\n\tdh_builddeb -- -Zxz\n'
                tree(root, rules)
                line = rules.splitlines().index(form) + 1
                with self.assertRaisesRegex(ValueError, rf'^debian/rules:{line}: Existing override_dh_builddeb: '
                                                        r'preserve and integrate its behavior explicitly$'):
                    prepare(root)
                self.assertEqual((root / 'debian/rules').read_text(), rules)
                self.assertFalse((root / 'debian/sparky-lean-toolkit').exists())

    def test_double_colon_hook_names_file_and_line(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rules = HEAD + 'execute_before_dh_auto_clean:: debian-clean\n\ndebian-clean:\n\ttrue\n'
            tree(root, rules)
            line = rules.splitlines().index('execute_before_dh_auto_clean:: debian-clean') + 1
            with self.assertRaisesRegex(ValueError, rf'^debian/rules:{line}: '):
                prepare(root)
            self.assertEqual((root / 'debian/rules').read_text(), rules)


if __name__ == '__main__':
    unittest.main()
