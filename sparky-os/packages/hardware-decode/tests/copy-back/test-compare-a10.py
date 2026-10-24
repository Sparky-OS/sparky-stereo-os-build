#!/usr/bin/env python3
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later
"""compare-a10.py on recorded fixtures: a case whose output was dimmed in one
phase only is confounded, not worse (the first ORDER 234 A10 run)."""
from pathlib import Path
import subprocess
import sys
import unittest

here = Path(__file__).resolve().parent


class Compare(unittest.TestCase):
    def test_dimmed_output_is_confounded_not_worse(self):
        fixtures = here/'fixtures/compare-a10'
        result = subprocess.run([sys.executable, '-I', str(here/'compare-a10.py'), str(fixtures/'before'), str(fixtures/'after')],
                                capture_output=True, text=True)
        lines = {line.split()[0]: line for line in result.stdout.splitlines() if line.startswith(('tv-', 'laptop-'))}
        self.assertIn('CONFOUNDED', lines['tv-3d-HDMI-A-1-vulkan-default-3d'])
        self.assertIn('dimmed to 63 nits, PQ', lines['tv-3d-HDMI-A-1-vulkan-default-3d'])
        self.assertIn(' ok ', lines['laptop-3d-eDP-1-vulkan-default-3d'])
        self.assertEqual(result.returncode, 2, result.stdout)


if __name__ == '__main__':
    unittest.main()
