# SPDX-License-Identifier: MIT
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from lean.debian_prepare import add_build_dependencies


@unittest.skipUnless(shutil.which('perl'), 'Dpkg Perl parser required')
class DependencyFields(unittest.TestCase):
    def test_license_preamble_is_not_a_source_stanza(self):
        preamble = '# Copyright fixture\n# SPDX-License-Identifier: Apache-2.0\n\n'
        source = 'Source: fixture\nBuild-Depends: cmake, googletest\n'
        binary = '\nPackage: fixture\nArchitecture: any\nDescription: fixture\n'
        revised = add_build_dependencies(preamble + source + binary, ['gcc'])
        self.assertTrue(revised.startswith(preamble))
        self.assertTrue(revised.endswith(binary))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'control'
            path.write_text(revised)
            script = '''use Dpkg::Control::Info; use Dpkg::Deps;
my $i = Dpkg::Control::Info->new($ARGV[0]);
die "Wrong source" unless $i->get_source->{'Source'} eq 'fixture';
my $d = deps_parse($i->get_source->{'Build-Depends'}, build_dep => 1);
die "Invalid dependency syntax" unless defined $d;
print $d->output();'''
            parsed = subprocess.check_output(['perl', '-e', script, str(path)], text=True)
        for name in ['gcc', 'cmake', 'googletest']:
            self.assertIn(name, parsed)

    def test_comments_between_continuations_keep_all_relations_parseable(self):
        control = '''Source: fixture
Build-Depends:
 debhelper-compat (= 13),
# Native tools are separate from target libraries.
 python3:any (>= 3.11),
# Preserve architecture and profile restrictions too.
 libfoo-dev [amd64] <!nocheck>,
Rules-Requires-Root: no

Package: fixture
Architecture: any
Depends: ${misc:Depends}
Description: fixture
'''
        revised = add_build_dependencies(control, ['gcc', 'python3-yaml'])
        self.assertIn(control.split('Build-Depends:', 1)[1], revised)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'control'
            path.write_text(revised)
            script = '''use Dpkg::Control::Info; use Dpkg::Deps;
my $i = Dpkg::Control::Info->new($ARGV[0]);
my $d = deps_parse($i->get_source->{'Build-Depends'}, build_dep => 1);
die "Invalid dependency syntax" unless defined $d;
print $d->output();'''
            parsed = subprocess.check_output(['perl', '-e', script, str(path)], text=True)
        for name in ['gcc', 'python3-yaml', 'debhelper-compat', 'python3:any', 'libfoo-dev']:
            self.assertIn(name, parsed)


if __name__ == '__main__':
    unittest.main()


class SourceDate(unittest.TestCase):
    """ORDER 421b: debian_prepare dates its entry by the recipe's SOURCE_DATE_EPOCH and stops without it; no clock fallback."""
    def tree(self, root):
        (root / 'debian').mkdir()
        (root / 'debian/rules').write_text('#!/usr/bin/make -f\n%:\n\tdh $@\n')
        (root / 'debian/control').write_text('Source: fixture\nBuild-Depends: debhelper-compat (= 13)\n\n'
                                             'Package: fixture\nArchitecture: any\nDescription: fixture\n')
        (root / 'debian/changelog').write_text('fixture (1) unstable; urgency=medium\n\n  * Fixture.\n\n'
                                               ' -- Example <example@example.invalid>  Tue, 20 Oct 2026 10:00:00 +0000\n')

    def test_without_a_date_it_stops_and_changes_nothing(self):
        from unittest import mock
        import os
        from lean.debian_prepare import prepare
        toolkit = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.tree(root)
            before = (root / 'debian/rules').read_text(), (root / 'debian/changelog').read_text()
            for value in (None, '', 'yesterday'):
                env = {k: v for k, v in os.environ.items() if k != 'SOURCE_DATE_EPOCH'}
                if value is not None:
                    env['SOURCE_DATE_EPOCH'] = value
                with mock.patch.dict(os.environ, env, clear=True):
                    with self.assertRaisesRegex(ValueError, 'SOURCE_DATE_EPOCH.*(not set|not a number).*clock'):
                        prepare(root, '1+lc1', toolkit)
            self.assertEqual(before, ((root / 'debian/rules').read_text(), (root / 'debian/changelog').read_text()))
            self.assertFalse((root / 'debian/sparky-lean-toolkit').exists())

    @unittest.skipUnless(shutil.which('dch') and shutil.which('dpkg-parsechangelog'), 'Debian source tools required')
    def test_with_a_date_the_entry_carries_it_in_utc(self):
        from unittest import mock
        import os
        from lean.debian_prepare import prepare
        toolkit = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.tree(root)
            with mock.patch.dict(os.environ, {'SOURCE_DATE_EPOCH': '1793974631', 'TZ': 'Asia/Tokyo',
                                             'DEBFULLNAME': 'Example', 'DEBEMAIL': 'example@example.invalid'}):
                prepare(root, '1+lc1', toolkit)
            self.assertIn('  Fri, 06 Nov 2026 14:17:11 +0000\n', (root / 'debian/changelog').read_text())

    def test_dh_after_one_make_variable_is_conventional_and_a_shell_prefix_is_not(self):
        # Debian's rustc: `$(SYSTEM_WORKAROUNDS) dh $@ --parallel --with bash-completion`
        from unittest import mock
        import os
        from lean.debian_prepare import prepare
        toolkit = Path(__file__).resolve().parents[2]
        env = {'SOURCE_DATE_EPOCH': '1793974631', 'DEBFULLNAME': 'Example', 'DEBEMAIL': 'example@example.invalid'}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.tree(root)
            (root / 'debian/rules').write_text('#!/usr/bin/make -f\n%:\n\t$(SYSTEM_WORKAROUNDS) dh $@ --parallel\n')
            with mock.patch.dict(os.environ, env):
                prepare(root, '1+lc1', toolkit)
            self.assertIn('lean.source_tree project', (root / 'debian/rules').read_text())
        for prefix in ('env X=1 ', 'cd sub && ', '$(lower) ', '$(A) $(B) '):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.tree(root)
                (root / 'debian/rules').write_text('#!/usr/bin/make -f\n%:\n\t' + prefix + 'dh $@\n')
                with mock.patch.dict(os.environ, env), self.assertRaisesRegex(ValueError, 'Not a conventional dh rules file'):
                    prepare(root, '1+lc1', toolkit)
