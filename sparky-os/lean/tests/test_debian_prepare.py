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
