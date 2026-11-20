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

    def test_shell_ulimit_inside_the_container(self):
        # Measured (ORDER 742): docker run --ulimit core=1 gives 1 byte; a recipe's own `ulimit -c 0` gives 0, which
        # runuser and bubblewrap keep, so a crash in the gate reached the host's crash list; `ulimit -c 1` asks for
        # 1024 bytes and fails (EPERM). Any core ulimit in a shell is a finding.
        # The cases are assembled so that this file is not a finding of the tree check itself.
        def ulimit(text):
            return corecheck.ulimit_findings('case.sh', text)
        zero, one, soft_zero = 'ulimit -c' + ' 0', 'ulimit -c' + ' 1', 'ulimit -Sc' + ' 0'
        self.assertEqual(len(ulimit(f"bash -c 'set -eu; {zero}; runuser -u builder -- make'")), 1)
        self.assertEqual(len(ulimit(f"bash -c 'set -eu; {one}; runuser -u builder -- make'")), 1)
        self.assertEqual(len(ulimit(f'{soft_zero}\n{one}')), 2)
        self.assertEqual(ulimit("bash -c 'set -eu; runuser -u builder -- make'"), [])
        self.assertEqual(ulimit(f'# {zero} was the old rule'), [])
        self.assertEqual(ulimit('ulimit -n 4096'), [])

    def test_python_argv(self):
        self.check("a = ['docker', 'run', '--ulimit', 'core=1', image]", 0, 'case.py')
        self.check("a = ['docker', 'run', image, '--ulimit', 'core=1']", 1, 'case.py')
        self.check("a = [self.docker, 'create', image]", 1, 'case.py')
        self.check("a = ['docker', 'run', '-d' if detach else '--rm', '--ulimit', 'core=1', image]", 0, 'case.py')
        self.assertEqual(self.check("s = \"docker run img\"", 0, 'case.py'), 0)


if __name__ == '__main__':
    unittest.main()
