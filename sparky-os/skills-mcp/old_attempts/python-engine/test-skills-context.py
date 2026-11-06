#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise offline context selection, boundaries and extraction, without a model."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'skills-context.py'
spec = importlib.util.spec_from_file_location('context', SCRIPT)
context = importlib.util.module_from_spec(spec)
spec.loader.exec_module(context)


class OfflineContext(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'reference'
        for name in context.COMMON:
            self.put(name, f'# {name}\nCommon guidance.\n')
        self.put('skills/demo/SKILL.md', '---\nname: demo\ndescription: Test.\n---\n'
                 '# Demo\n## First\nSelected.\n### Nested\nKeep nested.\n'
                 '```sh\n## False heading\n```\n## Second\nNot selected.\n')
        self.put('docs/example.md', '# A public reference\n')
        self.put('SOURCE', 'candidate\nbase test\n')
        self.put('private/mail.txt', 'Private sentinel.\n')
        self.put('tools/skills-context.py', SCRIPT.read_text())

    def put(self, name, text):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def cli(self, *args):
        return subprocess.run([sys.executable, str(self.root / 'tools/skills-context.py'), *args],
                              capture_output=True, text=True)

    def test_section_keeps_contract_and_nested_content(self):
        result = self.cli('--section', 'demo:First', '--reference', 'docs/example.md')
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in context.COMMON:
            self.assertIn(f'Source: {name}', result.stdout)
        self.assertIn('Keep nested.', result.stdout)
        self.assertIn('Full-file SHA256:', result.stdout)
        self.assertIn('name: demo', result.stdout)
        self.assertNotIn('Not selected.', result.stdout)
        self.assertNotIn('Private sentinel.', result.stdout)

    def test_list_sections_ignores_fenced_examples(self):
        result = self.cli('--list-sections', 'demo')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('False heading', result.stdout)
        self.assertIn('Nested', result.stdout)

    def test_limit_produces_no_partial_file(self):
        dest = self.base / 'context.txt'
        result = self.cli('demo', '--max-chars', '10', '--output', str(dest))
        self.assertEqual(result.returncode, 2)
        self.assertFalse(dest.exists())
        self.assertEqual(result.stdout, '')

    def test_existing_output_is_preserved(self):
        dest = self.base / 'context.txt'
        dest.write_text('Human notes')
        result = self.cli('demo', '--output', str(dest))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(dest.read_text(), 'Human notes')

    def test_unknown_and_ambiguous_sections_fail(self):
        for title in ('Absent', 'False heading'):
            self.assertEqual(self.cli('--section', f'demo:{title}').returncode, 2)
        p = self.root / 'skills/demo/SKILL.md'
        p.write_text(p.read_text() + '\n## First\nAmbiguous.\n')
        self.assertEqual(self.cli('--section', 'demo:First').returncode, 2)

    def test_private_absolute_parent_and_symlink_paths_refused(self):
        outside = self.base / 'secret.txt'
        outside.write_text('Secret sentinel')
        (self.root / 'docs/escape.md').symlink_to(outside)
        for path in ('private/mail.txt', str(outside), 'docs/../../secret.txt', 'docs/escape.md'):
            with self.subTest(path=path):
                result = self.cli('--reference', path)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn('Secret sentinel', result.stdout)

    def test_bundle_extracts_with_working_relative_paths(self):
        dest = self.base / 'reference.zip'
        self.assertEqual(self.cli('--bundle', str(dest)).returncode, 0)
        extracted = self.base / 'extracted'
        with zipfile.ZipFile(dest) as archive:
            self.assertNotIn('private/mail.txt', archive.namelist())
            archive.extractall(extracted)
        result = subprocess.run([sys.executable, str(extracted / 'tools/skills-context.py'),
                                 'demo', '--reference', 'docs/example.md'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('A public reference', result.stdout)
        self.assertIn('candidate', result.stdout)

    def test_bundle_cannot_contain_itself_or_replace_archive(self):
        self.assertEqual(self.cli('--bundle', str(self.root / 'docs/new.zip')).returncode, 2)
        self.assertFalse((self.root / 'docs/new.zip').exists())
        dest = self.base / 'existing.zip'
        dest.write_bytes(b'Keep this')
        self.assertEqual(self.cli('--bundle', str(dest)).returncode, 2)
        self.assertEqual(dest.read_bytes(), b'Keep this')

    def test_bundle_validates_symlinks_before_writing(self):
        secret = self.base / 'secret.txt'
        secret.write_text('Do not copy')
        (self.root / 'docs/escape.md').symlink_to(secret)
        dest = self.base / 'reference.zip'
        self.assertEqual(self.cli('--bundle', str(dest)).returncode, 2)
        self.assertFalse(dest.exists())


if __name__ == '__main__':
    unittest.main()
