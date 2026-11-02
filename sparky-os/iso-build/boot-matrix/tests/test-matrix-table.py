#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
"""Run with an optional matrix-table.py path to verify the pre-fix control too."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw

TABLE = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'matrix-table.py'
spec = importlib.util.spec_from_file_location('matrix_table', TABLE)
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)


class LatestMetadata(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.old = self.make_run('old/seabios-cd', 12)
        self.new = self.make_run('new/seabios-cd', 37)
        self.metadata = self.new / 'result.json'
        self.assertEqual(matrix.cell([str(self.old)]), 'pass 12s')

    def make_run(self, name, seconds, desktop=True):
        path = self.root / name
        path.mkdir(parents=True)
        frame = Image.new('RGB', (100, 100), (0, 0, 180) if desktop else (0, 0, 0))
        if desktop:
            ImageDraw.Draw(frame).rectangle((20, 25, 79, 65), fill='white')
        frame.save(path / 't1.png')
        (path / 'result.json').write_text(json.dumps({'steps': [{'shot': 't1', 't': seconds}]}))
        return path

    def assert_metadata_failure(self, exception):
        for paths in ([str(self.new)], [str(self.old), str(self.new)]):
            with self.subTest(paths=paths):
                result = matrix.cell(paths)
                self.assertTrue(result.startswith('fail: metadata error:'), result)
                self.assertIn(str(self.metadata), result)
                self.assertIn(exception, result)
                self.assertNotIn('pass ', result)

    def test_missing_metadata(self):
        self.metadata.unlink()
        self.assert_metadata_failure('FileNotFoundError')

    def test_truncated_json(self):
        self.metadata.write_text('{"steps": [')
        self.assert_metadata_failure('JSONDecodeError')

    def test_invalid_encoding(self):
        self.metadata.write_bytes(b'\xff')
        self.assert_metadata_failure('UnicodeDecodeError')

    def test_permission_denied(self):
        self.assertNotEqual(os.geteuid(), 0, 'Run as an unprivileged user to exercise EACCES')
        self.metadata.chmod(0)
        self.addCleanup(self.metadata.chmod, 0o600)
        self.assert_metadata_failure('PermissionError')

    def test_metadata_is_directory(self):
        self.metadata.unlink()
        self.metadata.mkdir()
        self.assert_metadata_failure('IsADirectoryError')

    def test_unreadable_step_structure(self):
        for value, exception in (([], 'AttributeError'), ({'steps': None}, 'TypeError')):
            with self.subTest(value=value):
                self.metadata.write_text(json.dumps(value))
                self.assert_metadata_failure(exception)

    def test_later_valid_run_overrides_failure(self):
        self.metadata.write_text('{')
        later = self.make_run('later/seabios-cd', 51)
        self.assertEqual(matrix.cell([str(self.old), str(self.new), str(later)]), 'pass 51s')

    def test_valid_runs_keep_argument_order(self):
        os.utime(self.old, (2000000000, 2000000000))
        os.utime(self.new, (1000000000, 1000000000))
        self.assertEqual(matrix.cell([str(self.old), str(self.new)]), 'pass 37s')
        self.assertEqual(matrix.cell([str(self.new), str(self.old)]), 'pass 12s')

    def test_valid_failure_overrides_pass(self):
        failed = self.make_run('failed/seabios-cd', 50, desktop=False)
        self.assertEqual(matrix.cell([str(self.old), str(failed)]), 'fail: black screen')
        (failed / 'serial.log').write_text('Security Policy Violation')
        self.assertEqual(matrix.cell([str(self.old), str(failed)]), 'fail: Security Policy Violation')

    def test_no_run_and_partial_rerun(self):
        absent = str(self.root / 'absent/seabios-cd')
        self.assertEqual(matrix.cell([]), '-')
        self.assertEqual(matrix.cell([absent]), '-')
        self.assertEqual(matrix.cell([str(self.old), absent]), 'pass 12s')

    def test_cli_reports_error_in_only_affected_cell(self):
        self.metadata.write_text('{')
        self.make_run('old/seabios-usb', 20)
        self.make_run('new/seabios-usb', 45)
        result = subprocess.run([sys.executable, str(TABLE),
                                 f'fixture={self.old.parent}+{self.new.parent}#seabios'],
                                text=True, capture_output=True, check=True)
        row = next(line for line in result.stdout.splitlines() if line.startswith('| seabios |'))
        self.assertIn('fail: metadata error:', row)
        self.assertIn(str(self.metadata), row)
        self.assertIn('JSONDecodeError', row)
        self.assertTrue(row.endswith('| pass 45s |'), row)
        self.assertNotIn('pass 12s', row)

    def test_error_keeps_markdown_cell_intact(self):
        odd = self.make_run('odd|<run>\n/seabios-cd', 60)
        (odd / 'result.json').unlink()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            matrix.table('fixture', str(odd.parent), ['seabios'])
        rows = [line for line in output.getvalue().splitlines() if line.startswith('| seabios |')]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].count('|'), 4, rows[0])
        self.assertIn('odd&#124;&lt;run&gt;', rows[0])
        self.assertIn('FileNotFoundError', rows[0])


    def test_desktop_time_missing(self):
        for steps in ([], [{'shot': 'other', 't': 20}], [{'shot': 't1'}],
                      [{'shot': 't1', 't': None}]):
            self.metadata.write_text(json.dumps({'steps': steps}))
            for paths in ([str(self.new)], [str(self.old), str(self.new)]):
                with self.subTest(steps=steps, paths=paths):
                    result = matrix.cell(paths)
                    self.assertTrue(result.startswith('fail: metadata error:'), result)
                    self.assertIn(str(self.new / 't1.png'), result)
                    self.assertIn('time is missing', result)
                    self.assertIn(str(self.metadata), result)

    def test_first_desktop_without_time_is_not_replaced(self):
        (self.new / 't2.png').write_bytes((self.new / 't1.png').read_bytes())
        self.metadata.write_text(json.dumps({'steps': [{'shot': 't2', 't': 60}]}))
        result = matrix.cell([str(self.old), str(self.new)])
        self.assertIn('t1.png: time is missing', result)
        self.assertNotIn('pass ', result)

    def test_other_shot_missing_timestamp_still_fails(self):
        black = self.make_run('black/seabios-cd', 30, desktop=False)
        (black / 'result.json').write_text('{"steps": [{"shot": "t1"}]}')
        self.assertTrue(matrix.cell([str(black)]).startswith('fail: metadata error:'))

    def test_zero_desktop_time_is_valid(self):
        self.metadata.write_text(json.dumps({'steps': [{'shot': 't1', 't': 0}]}))
        self.assertEqual(matrix.cell([str(self.new)]), 'pass 0s')

    def test_serial_permission_denied(self):
        self.assertNotEqual(os.geteuid(), 0, 'Run as an unprivileged user to exercise EACCES')
        black = self.make_run('black/seabios-cd', 30, desktop=False)
        for path in (black, self.new):
            log = path / 'serial.log'
            log.write_text('Security Policy Violation')
            log.chmod(0)
            self.addCleanup(log.chmod, 0o600)
            for paths in ([str(path)], [str(self.old), str(path)]):
                with self.subTest(paths=paths):
                    result = matrix.cell(paths)
                    self.assertTrue(result.startswith('fail: serial log error:'), result)
                    self.assertIn(str(log), result)
                    self.assertIn('PermissionError', result)

    def test_other_serial_read_errors(self):
        black = self.make_run('black/seabios-cd', 30, desktop=False)
        log = black / 'serial.log'
        log.mkdir()
        result = matrix.cell([str(self.old), str(black)])
        self.assertIn('fail: serial log error:', result)
        self.assertIn(str(log), result)
        self.assertIn('IsADirectoryError', result)
        log.rmdir()
        log.symlink_to('serial.log')
        result = matrix.cell([str(black)])
        self.assertIn('fail: serial log error:', result)
        self.assertIn(str(log), result)
        self.assertIn('OSError', result)

    def test_absent_and_readable_serial_keep_classification(self):
        black = self.make_run('black/seabios-cd', 30, desktop=False)
        for content in (None, '', 'ordinary boot output', 'boot bytes: \ufffd'):
            with self.subTest(content=content):
                for path in (black, self.new):
                    if content is not None:
                        (path / 'serial.log').write_text(content)
                self.assertEqual(matrix.cell([str(black)]), 'fail: black screen')
                self.assertEqual(matrix.cell([str(self.new)]), 'pass 37s')
        (black / 'serial.log').write_text('Verifying shim SBAT data failed')
        self.assertEqual(matrix.cell([str(black)]), 'fail: shim: SBAT verification failed')
        (self.new / 'serial.log').write_text('Verifying shim SBAT data failed')
        self.assertEqual(matrix.cell([str(self.new)]), 'pass 37s')

    def test_cli_time_and_serial_errors_do_not_abort_other_cells(self):
        self.make_run('old/seabios-usb', 20)
        self.make_run('new/seabios-usb', 45)
        for failure in ('time', 'serial'):
            with self.subTest(failure=failure):
                self.metadata.write_text(json.dumps({'steps': [] if failure == 'time' else [{'shot': 't1', 't': 37}]}))
                if failure == 'serial':
                    (self.new / 'serial.log').mkdir()
                result = subprocess.run([sys.executable, str(TABLE),
                                         f'fixture={self.old.parent}+{self.new.parent}#seabios'],
                                        text=True, capture_output=True, check=True)
                row = next(line for line in result.stdout.splitlines() if line.startswith('| seabios |'))
                self.assertIn('time is missing' if failure == 'time' else 'IsADirectoryError', row)
                self.assertTrue(row.endswith('| pass 45s |'), row)
                self.assertNotIn('pass 12s', row)

    def test_followup_diagnostics_keep_markdown_intact(self):
        odd = self.make_run('odd|<run>\n/seabios-cd', 60)
        (odd / 'result.json').write_text('{"steps": []}')
        for failure in ('time', 'serial'):
            with self.subTest(failure=failure):
                if failure == 'serial':
                    (odd / 'serial.log').mkdir()
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    matrix.table('fixture', str(odd.parent), ['seabios'])
                row = next(line for line in output.getvalue().splitlines() if line.startswith('| seabios |'))
                self.assertEqual(row.count('|'), 4, row)
                self.assertIn('odd&#124;&lt;run&gt;', row)
                self.assertIn('time is missing' if failure == 'time' else 'IsADirectoryError', row)


if __name__ == '__main__':
    unittest.main(verbosity=2)
