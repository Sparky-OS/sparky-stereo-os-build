#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Debian's task packages are found by their source, retired with their payload kept, and a failure says its cause."""
import ast
from pathlib import Path
import re
import subprocess
import unittest
from unittest.mock import patch

RECIPE = Path(__file__).resolve().parents[1]
WANTED = ('Blocked', 'installed', 'debian_tasks', 'held', 'removals', 'keep_payload', 'names', 'actual', 'failure')


class Result:
    def __init__(self, stdout):
        self.stdout = stdout
        self.returncode = 0


class DebianTaskTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tree = ast.parse((RECIPE / 'bin/languages').read_text())
        tree.body = [node for node in tree.body
                     if (isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in WANTED)
                     or (isinstance(node, ast.Assign) and getattr(node.targets[0], 'id', '') in ('LIVE', 'NETWORK'))]
        cls.code = compile(tree, 'bin/languages', 'exec')

    def namespace(self, answers):
        calls = []

        def run(args, check=True):
            calls.append(args)
            return Result(answers[args[0]])
        space = {'re': re, 'DRY': False, 'run': run, 'subprocess': subprocess, 'Path': Path}
        exec(self.code, space)
        space['calls'] = calls
        return space

    STATUS = ('task-laptop\tinstalled\ttasksel\n'
              'task-english\tinstalled\ttasksel (3.91)\n'
              'task-sparky-language-pt-br\tinstalled\tsparky-stereo-language-meta\n'
              'task-sparky-stereo-gamer\tinstalled\t\n'
              'task-rescue\tinstalled\tsome-other-source\n'
              'task-ssh-server\tconfig-files\ttasksel\n'
              'tasksel\tinstalled\ttasksel\n'
              'tasksel-data\tinstalled\ttasksel\n')

    def test_debian_tasks_are_found_by_their_source(self):
        space = self.namespace({'dpkg-query': self.STATUS})
        self.assertEqual(space['debian_tasks'](), {'task-laptop', 'task-english'})

    def packages(self, tasksel_deps):
        return ('tasksel\tinstalled\tdebconf, apt\t\n'
                'task-laptop\tinstalled\t' + tasksel_deps + ', anacron, bluetooth, powertop\t\n'
                'anacron\tinstalled\t\t\nbluetooth\tinstalled\t\t\npowertop\tinstalled\t\t\n')

    def held(self, deps, policy):
        space = self.namespace({})

        def run(args, check=True):
            if args[0] == 'dpkg-query' and '${Source}' in args[3]:
                return Result('task-laptop\tinstalled\ttasksel\ntasksel\tinstalled\ttasksel\n')
            if args[0] == 'dpkg-query':
                return Result(self.packages(deps))
            return Result(policy)
        space['run'] = run
        return space['held']()

    def test_held_only_when_a_task_is_locked_to_the_installed_version(self):
        old = 'Installed: 3.91\n  Candidate: 3.92\n'
        same = 'Installed: 3.92\n  Candidate: 3.92\n'
        self.assertTrue(self.held('tasksel (= 3.91)', old))
        self.assertFalse(self.held('tasksel (= 3.91)', same))
        self.assertFalse(self.held('tasksel (>= 3.80)', old))

    def test_what_a_retired_task_brought_is_marked_manual(self):
        space = self.namespace({'dpkg-query': self.packages('tasksel (= 3.91)'), 'apt-mark': ''})
        have = space['installed']()
        kept = space['keep_payload']({'task-laptop'}, have, {'task-laptop'})
        self.assertEqual(kept, {'anacron', 'bluetooth', 'powertop'})
        marks = [c for c in space['calls'] if c[0] == 'apt-mark']
        self.assertEqual(marks, [['apt-mark', 'manual', 'anacron', 'bluetooth', 'powertop']])

    def test_removals_read_both_remove_and_purge_lines(self):
        space = self.namespace({})
        text = 'Inst x\nRemv task-laptop [3.91]\nPurg other:amd64 [1]\n'
        self.assertEqual(space['removals'](Result(text)), {'task-laptop', 'other'})

    def test_failure_names_the_cause(self):
        space = self.namespace({})
        failure, blocked = space['failure'], space['Blocked']
        self.assertEqual(failure(blocked({'task-laptop', 'powertop'})), ('LOCAL3', 'powertop, task-laptop'))
        self.assertEqual(failure(RuntimeError('Err:1 https://deb.debian.org/debian testing InRelease\n  Could not resolve host'))[0], 'LOCAL2')
        key, text = failure(RuntimeError('Reading package lists...\nE: Unable to satisfy dependencies. Reached two conflicting assignments:\n   1. a=1 is selected\n   2. b Depends a (= 2)\n'))
        self.assertEqual((key, text), ('LOCAL4', 'E: Unable to satisfy dependencies. Reached two conflicting assignments: 1. a=1 is selected 2. b Depends a (= 2)'))
        self.assertEqual(failure(RuntimeError(''))[0], 'LOCAL4')


if __name__ == '__main__':
    unittest.main()
