#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the wrapper against a deliberately lossy inhibitor stand-in."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


class InhibitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copyfile(Path(__file__).with_name('inhibit.py'), self.root/'inhibit.py')
        fake = self.root/'kde-inhibit'
        fake.write_text('#!/usr/bin/env python3\nimport os,subprocess,sys\n'
            'if os.environ.get("FAIL_INHIBIT"): print("Inhibit failed: test service missing",file=sys.stderr,flush=True)\n'
            'subprocess.run(sys.argv[4:])\n')  # Deliberately discards the child exit code like KDE's tool.
        fake.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root)+':'+os.environ['PATH'], XDG_RUNTIME_DIR=str(self.root))
        self.argv = [sys.executable, str(self.root/'inhibit.py')]

    def test_child_status_survives_lossy_wrapper(self):
        (self.root/'bench.py').write_text('raise SystemExit(37)\n')
        result = subprocess.run(self.argv, env=self.env, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 37)

    def test_inhibit_failure_stops_before_bench(self):
        marker = self.root/'unexpected-bench'
        (self.root/'bench.py').write_text(f'from pathlib import Path\nPath({str(marker)!r}).touch()\n')
        result = subprocess.run(self.argv, env=dict(self.env, FAIL_INHIBIT='1'), capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b'KDE inhibition failed', result.stderr)
        self.assertFalse(marker.exists())

    def test_term_keeps_wrapper_until_child_cleanup(self):
        ready, restored = self.root/'ready', self.root/'restored'
        (self.root/'bench.py').write_text('from pathlib import Path\nimport time\n'
            f'Path({str(ready)!r}).touch()\ntry:\n time.sleep(30)\nfinally:\n Path({str(restored)!r}).touch()\n')
        process = subprocess.Popen(self.argv, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic()+5
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(.05)
            self.assertTrue(ready.exists())
            child_pids = list(self.root.glob('bino-242-inhibit-*/child.pid'))
            self.assertEqual(len(child_pids), 1)
            child_pid = int(child_pids[0].read_text())
            self.assertNotEqual(os.getsid(child_pid), os.getsid(process.pid))
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130)
            self.assertTrue(restored.exists())
        finally:
            if process.poll() is None:
                process.kill(); process.communicate()


if __name__ == '__main__': unittest.main()
