# SPDX-License-Identifier: MIT
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('replacement', Path(__file__).with_name('check-replacement-versions.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def row(version, name='kernel-meta', arch='all', variant=''):
    return {'Package': name, 'Version': version, 'Architecture': arch, 'Architecture-Variant': variant}


class ReplacementVersions(unittest.TestCase):
    def test_kernel_suffix_regression_and_correction(self):
        old = [row('7.3.4+stereo3d18.703+lc1')]
        for new, expected in [('7.3.4+stereo3d18+round20261121.794', 'FAIL'),
                              ('7.3.4+stereo3d18.703+lc1', 'FAIL'),
                              ('7.3.4+stereo3d18.794+lc1', 'PASS')]:
            with self.subTest(new=new):
                self.assertEqual(module.check([row(new)], old)[0]['verdict'], expected)

    def test_epoch_and_debian_ordering(self):
        self.assertEqual(module.check([row('1:2.0-1')], [row('9.0-1')])[0]['verdict'], 'PASS')
        self.assertEqual(module.check([row('1.0~rc1')], [row('1.0')])[0]['verdict'], 'FAIL')

    def test_each_architecture_and_highest_published_version(self):
        old = [row('1', arch='amd64'), row('2', arch='i386'), row('1', arch='all')]
        result = module.check([row('3', arch='amd64'), row('2', arch='i386')], old)
        self.assertEqual([r['verdict'] for r in result], ['PASS', 'FAIL'])
        self.assertEqual([r['published'] for r in result], ['2', '2'])

    def test_new_name_and_distinct_variant(self):
        self.assertEqual(module.check([row('1', name='new')], [row('9')])[0]['verdict'], 'new binary name')
        self.assertEqual(module.check([row('2')], [row('1'), row('99', variant='x86-64-v3')])[0]['verdict'], 'PASS')

    def test_empty_candidates_refused(self):
        with self.assertRaises(ValueError):
            module.check([], [row('1')])


if __name__ == '__main__':
    unittest.main()
