#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Static red/green cases for container core-limit wiring; no Docker runs."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('corecheck', Path(__file__).with_name('check-container-core.py'))
corecheck = importlib.util.module_from_spec(spec)
spec.loader.exec_module(corecheck)


class CoreLimits(unittest.TestCase):
    def check(self, text, bad, rel='case.sh'):
        findings, count = corecheck.findings(rel, text)
        self.assertEqual(len(findings), bad, findings)
        return count

    def test_missing_and_zero(self):
        self.check('docker run --rm img true', 1)
        self.check('docker create --ulimit core=0 img', 1)
        self.check('docker run --ulimit core=0:0 img true', 1)
        self.check('docker run --ulimit core=1 img true', 0)
        self.check('docker create --ulimit=core=1 img', 0)

    def test_continuation(self):
        self.check('docker run --rm \\\n --ulimit core=1 img true', 0)

    def test_each_launcher(self):
        self.assertEqual(self.check('docker run --ulimit core=1 img true\ndocker run img true', 1), 2)
        self.assertEqual(self.check('docker run --ulimit core=1 img true; docker run img true', 1), 2)

    def test_payload_flag_does_not_protect(self):
        self.check("docker run img echo '--ulimit core=1'", 1)
        self.check("docker run img sh -c 'docker run --ulimit core=1 img true'", 1)

    def test_array_must_be_used(self):
        prefix = 'common=(--rm --ulimit core=1 --cpus 4)\n'
        self.check(prefix + 'docker run "${common[@]}" img true', 0)
        self.check(prefix + 'docker run img true', 1)
        self.check(prefix.replace('core=1', 'core=0') + 'docker run "${common[@]}" img true', 1)

    def test_comments_and_inspection_are_not_launchers(self):
        self.assertEqual(self.check('# docker run img\ngrep "docker run" file', 0), 0)

    def test_python_argv(self):
        self.check("a = ['docker', 'run', '--ulimit', 'core=1', image]", 0, 'case.py')
        self.check("a = ['docker', 'run', image, '--ulimit', 'core=1']", 1, 'case.py')
        self.check("a = [self.docker, 'create', image]", 1, 'case.py')
        self.check("a = ['docker', 'run', '-d' if detach else '--rm', '--ulimit', 'core=1', image]", 0, 'case.py')
        self.assertEqual(self.check("s = \"docker run img\"", 0, 'case.py'), 0)


if __name__ == '__main__':
    unittest.main()
