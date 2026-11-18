#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""A failed disk measurement must stop only the named task."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class BudgetTests(unittest.TestCase):
    def test_unreadable_scratch_stops_named_container(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'du').write_text('#!/bin/sh\necho unreadable >&2\nexit 1\n')
            (root / 'docker').write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$STOP_RECORD"\n')
            for name in ('du', 'docker'):
                (root / name).chmod(0o755)
            env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'], STOP_RECORD=str(root / 'stopped'))
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name('budget-run.py')),
                '--scratch', str(root), '--scratch-gib', '9',
                '--container', 'rp701-fixture', '--log', str(root / 'child.log'),
                '--', sys.executable, '-c', 'pass'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
            self.assertIn('scratch measurement failed', result.stdout)
            self.assertEqual((root / 'stopped').read_text().splitlines(),
                             ['stop', '--timeout', '5', 'rp701-fixture'])


if __name__ == '__main__':
    unittest.main()
