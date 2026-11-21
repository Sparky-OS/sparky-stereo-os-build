#!/usr/bin/python3
import concurrent.futures
import importlib.machinery
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
seed = importlib.machinery.SourceFileLoader('vibe_seed', str(ROOT / 'bin/seed')).load_module()


class SeedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = patch.dict(os.environ, {'XDG_DATA_HOME': self.tmp.name})
        self.env.start(); self.addCleanup(self.env.stop)
        self.presets = patch.object(seed, 'PRESETS', ROOT / 'presets')
        self.presets.start(); self.addCleanup(self.presets.stop)
        self.target = Path(self.tmp.name) / 'github.com.thewh1teagle.vibe/app_config.json'

    def test_preserve_existing_even_invalid_json(self):
        self.target.parent.mkdir()
        original = b'person-owned\x00bytes'
        self.target.write_bytes(original)
        with patch.object(seed, 'gpu_facts', side_effect=AssertionError('must not probe')):
            self.assertFalse(seed.seed())
        self.assertEqual(self.target.read_bytes(), original)

    def test_dangling_symlink_is_existing(self):
        self.target.parent.mkdir(); self.target.symlink_to('absent')
        self.assertFalse(seed.seed())
        self.assertTrue(self.target.is_symlink())

    def test_concurrent_atomic_create(self):
        with patch.object(seed, 'gpu_facts', return_value=(None, False)):
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
                result = list(pool.map(lambda _: seed.seed('light'), range(20)))
        self.assertEqual(sum(result), 1)
        values = json.loads(self.target.read_text())
        self.assertTrue(values['model.path'].endswith('/ggml-medium-q8_0.bin'))
        self.assertFalse(values['analytics_enabled'])
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.target.parent.glob('.app_config.*')), [])

    def test_appearing_file_is_not_replaced(self):
        original_link = os.link
        def competing_writer(src, dst):
            Path(dst).write_bytes(b'person won the race')
            return original_link(src, dst)
        with patch.object(seed, 'gpu_facts', return_value=(None, False)), patch.object(seed.os, 'link', competing_writer):
            self.assertFalse(seed.seed('default'))
        self.assertEqual(self.target.read_bytes(), b'person won the race')

    def test_two_identical_physical_cards_are_uncertain(self):
        import subprocess
        answers = [subprocess.CompletedProcess([], 0, 'pci-0000:01:00.0\n', ''),
                   subprocess.CompletedProcess([], 0, json.dumps([
                       {'id': 'pci-0000:01:00.0', 'name': 'Same GPU'},
                       {'id': 'pci-0000:02:00.0', 'name': 'Same GPU'}]), ''),
                   subprocess.CompletedProcess([], 0, json.dumps([
                       {'index': 0, 'description': 'Same GPU'}]), '')]
        with patch.object(seed.subprocess, 'run', side_effect=answers):
            self.assertEqual(seed.gpu_facts(), (None, True))

    def test_mapping_never_guesses(self):
        devices = [{'index': 2, 'name': 'Vulkan0', 'description': 'AMD Example'},
                   {'index': 5, 'name': 'CUDA0', 'description': 'NVIDIA Example'}]
        self.assertEqual(seed.match_device('AMD Example', devices), 2)
        self.assertEqual(seed.match_device('NVIDIA Example', devices), 5)
        self.assertIsNone(seed.match_device('AMD', devices))
        self.assertIsNone(seed.match_device('AMD Example', devices + devices))


unittest.main()
