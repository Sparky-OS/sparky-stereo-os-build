#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""A failed disk measurement must stop only the named task."""
import os
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class BudgetTests(unittest.TestCase):
    def test_metrics_keep_peak_after_usage_falls_and_propagate_child_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'du').write_text('#!/bin/sh\nif [ -f "$SAMPLE_SEEN" ]; then echo "1024 scratch"; '
                                    'else touch "$SAMPLE_SEEN"; echo "2048 scratch"; fi\n')
            (root / 'du').chmod(0o755)
            env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'], SAMPLE_SEEN=str(root / 'seen'))
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name('budget-run.py')),
                '--scratch', str(root), '--scratch-gib', '1', '--root-min-free-gib', '0',
                '--build-min-free-gib', '0', '--interval-seconds', '0.02',
                '--metrics', str(root / 'metrics.jsonl'), '--container', 'rp701-fixture',
                '--log', str(root / 'child.log'), '--', sys.executable, '-c',
                'import time; time.sleep(0.15); raise SystemExit(7)'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
            samples = [json.loads(line) for line in (root / 'metrics.jsonl').read_text().splitlines()]
            self.assertGreaterEqual(len(samples), 2)
            self.assertEqual(samples[-1]['event'], 'finished')
            self.assertEqual(samples[-1]['scratch_bytes'], 1024)
            self.assertEqual(samples[-1]['peak_scratch_bytes'], 2048)

    def test_zero_sampling_interval_refuses_before_starting_command(self):
        for value in ('0', 'nan', 'inf'):
            with self.subTest(value=value):
                result = subprocess.run([sys.executable, str(Path(__file__).with_name('budget-run.py')),
                                         '--interval-seconds', value], capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn('sampling interval must be positive', result.stderr)

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
