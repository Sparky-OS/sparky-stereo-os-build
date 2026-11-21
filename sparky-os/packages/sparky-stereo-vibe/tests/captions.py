#!/usr/bin/python3
import importlib.machinery
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
caption = importlib.machinery.SourceFileLoader('vibe_captions', str(ROOT/'bin/captions')).load_module()


class CaptionsTest(unittest.TestCase):
    def setUp(self):
        self.gpu = patch.object(caption.runpy, 'run_path', return_value={'gpu_facts': lambda: (None, False)})
        self.gpu.start();self.addCleanup(self.gpu.stop)
        self.tmp = tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.media = Path(self.tmp.name)/'name with spaces.mkv';self.media.write_bytes(b'original movie')
        self.output = self.media.with_suffix('.srt')
        self.result = subprocess.CompletedProcess([], 0, '[00:00:01.230 --> 00:00:02.450] Hello.\n', '')

    def test_sibling_and_source_integrity(self):
        with patch.object(caption.subprocess, 'run', return_value=self.result):
            self.assertTrue(caption.caption(self.media, {}, Path('/model.bin')))
        self.assertEqual(self.media.read_bytes(), b'original movie')
        self.assertEqual(self.output.read_text(), '1\n00:00:01,230 --> 00:00:02,450\nHello.\n\n')

    def test_existing_srt_kept(self):
        self.output.write_bytes(b'person captions')
        with patch.object(caption.subprocess, 'run', side_effect=AssertionError('no engine invocation')):
            self.assertFalse(caption.caption(self.media, {}, Path('/model.bin')))
        self.assertEqual(self.output.read_bytes(), b'person captions')

    def test_failed_engine_leaves_no_srt_or_partial(self):
        with patch.object(caption.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, [], stderr='invalid model')):
            with self.assertRaises(subprocess.CalledProcessError):caption.caption(self.media, {}, Path('/model.bin'))
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.media.parent.glob('.*')), [])

    def test_racing_caption_writer_wins(self):
        def complete(*args, **kwargs):
            self.output.write_bytes(b'concurrent captions')
            return self.result
        with patch.object(caption.subprocess, 'run', side_effect=complete):
            self.assertFalse(caption.caption(self.media, {}, Path('/model.bin')))
        self.assertEqual(self.output.read_bytes(), b'concurrent captions')

    def test_untimed_output_is_not_invented(self):
        with self.assertRaises(ValueError):caption.to_srt('plain text without timestamps')
        self.assertEqual(caption.to_srt(''), '')

unittest.main()
