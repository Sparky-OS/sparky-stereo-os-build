#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check that a task or symptom finds its skill offline: no model, no network, the same answer every time."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TREE = Path(__file__).resolve().parents[2]
SCRIPT = TREE / 'tools/skills-context.py'

# Symptoms met in the edition's work in October 2026, as a person would type them, and the skill that answers each.
SYMPTOMS = (
    ('an apt pin that ignores i386', 'edition-packaging'),
    ('a Codex lane that stops after two runs without a tool call', 'ai-partners'),
    ('a KWin eye that differs at alpha edges', 'stereo-proof-rig'),
    ('a SPICE migration that loses the cache', 'stereo-vm'),
    ('a DXVK PE debug CRC mismatch', 'proton-wine'),
    ('an HDMI 3D mode missing from the EDID', 'drivers'),
    ('an ISO uploaded as a GitHub release that Zenodo keeps', 'forks-and-online'),
    ('zfs-dkms does not build on the new kernel', 'drivers'),
    ('Steam games cannot connect to the wayland socket or pipewire', 'proton-wine'),
    ('a showcase stereo screenshot that reads flat', 'stereo-proof-rig'),
)


def run(script, *args, env=None):
    return subprocess.run([sys.executable, '-I', str(script), *args], capture_output=True, text=True, env=env)


def ranked(stdout):
    return [line.split()[1] for line in stdout.splitlines() if line[:1].isdigit() and '. ' in line]


class RealSymptoms(unittest.TestCase):
    """The installed or checked-out tree itself: each symptom's skill ranks first."""

    def test_each_symptom_ranks_its_skill_first(self):
        for symptom, skill in SYMPTOMS:
            with self.subTest(symptom=symptom):
                result = run(SCRIPT, '--find', symptom)
                self.assertEqual(result.returncode, 0, result.stderr)
                names = ranked(result.stdout)
                self.assertTrue(names, result.stdout)
                self.assertEqual(names[0], skill, result.stdout)

    def test_result_names_the_file_and_the_next_command(self):
        result = run(SCRIPT, '--find', SYMPTOMS[0][0], '--limit', '1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(ranked(result.stdout)), 1)
        self.assertIn(str(TREE / 'skills/edition-packaging/SKILL.md'), result.stdout)
        self.assertIn('skills-context.py edition-packaging', result.stdout)
        named = run(SCRIPT, '--find', SYMPTOMS[0][0], '--limit', '1', '--context-command', 'sparky-stereo-skills context')
        self.assertIn('Next: sparky-stereo-skills context edition-packaging', named.stdout)

    def test_same_answer_every_time_and_without_environment(self):
        first = run(SCRIPT, '--find', SYMPTOMS[2][0])
        second = run(SCRIPT, '--find', SYMPTOMS[2][0], env={'PATH': os.defpath})
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)


class Fixture(unittest.TestCase):
    """A small tree: what is ranked, from which fields, and what is refused."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name) / 'reference'
        self.put('skills/alpha-skill/SKILL.md', '---\nname: alpha-skill\ndescription: Repair the widget frobnicator.\n---\n# A\nbody mentions zebra\n')
        self.put('skills/beta-skill/SKILL.md', '---\nname: beta-skill\ndescription: >-\n  Tune the gadget\n  and its frobnicator.\n---\n# B\n')
        self.put('skills/gamma-skill/SKILL.md', '---\nname: gamma-skill\ndescription: Something else entirely.\n---\n# C\n')
        self.put('skills/README.md', '| Your task | Read next |\n| --- | --- |\n'
                 '| Quokka handling | [gamma-skill](gamma-skill/SKILL.md) |\n')
        self.put('tools/skills-context.py', SCRIPT.read_text())
        self.script = self.root / 'tools/skills-context.py'

    def put(self, name, text):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def test_name_outranks_description(self):
        result = run(self.script, '--find', 'beta frobnicator')
        self.assertEqual(ranked(result.stdout)[:2], ['beta-skill', 'alpha-skill'], result.stdout)

    def test_folded_description_and_plural_forms_match(self):
        result = run(self.script, '--find', 'gadgets tuning')
        self.assertEqual(ranked(result.stdout), ['beta-skill'], result.stdout)

    def test_readme_task_table_routes_to_its_skill(self):
        result = run(self.script, '--find', 'handling a quokka')
        self.assertEqual(ranked(result.stdout), ['gamma-skill'], result.stdout)

    def test_body_text_is_not_searched(self):
        result = run(self.script, '--find', 'zebra')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(ranked(result.stdout), [])
        self.assertIn('README.md', result.stdout + result.stderr)

    def test_empty_query_and_mixed_operations_refused(self):
        for args in ((' the of ',), ('frobnicator', '--bundle', str(self.root.parent / 'x.zip')), ('frobnicator', '--limit', '0')):
            with self.subTest(args=args):
                result = run(self.script, '--find', *args)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn('unrecognized arguments', result.stderr)
                self.assertFalse((self.root.parent / 'x.zip').exists())


if __name__ == '__main__':
    unittest.main()
