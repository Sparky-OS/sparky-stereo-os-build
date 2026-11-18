"""A green empty simulation must not certify the old edition as uplifted."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('upgrade_targets', Path(__file__).parent/'proof/check-upgrade-targets.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Targets(unittest.TestCase):
    def test_wrong_origin_is_refused(self):
        checked, failures = module.verify('ii pkg:amd64 1\n', '0 upgraded, 0 to remove\n', 'pkg:amd64 2\n')
        self.assertEqual(checked, 1)
        self.assertEqual(len(failures), 1)

    def test_exact_native_and_foreign_targets(self):
        checked, failures = module.verify('ii pkg:amd64 1\nii pkg:i386 1\n',
            'Inst pkg [1] (2 Local [amd64])\nInst pkg:i386 [1] (2 Local [i386])\n',
            'pkg:amd64 2\npkg:i386 2\n')
        self.assertEqual((checked, failures), (2, []))

    def test_wrong_offered_version_is_refused(self):
        _, failures = module.verify('ii pkg:all 1\n', 'Inst pkg [1] (1.5 Local [all])\n', 'pkg:all 2\n')
        self.assertEqual(len(failures), 1)

    def test_no_installed_target_is_refused(self):
        _, failures = module.verify('', '', 'pkg:all 2\n')
        self.assertEqual(len(failures), 1)


if __name__ == '__main__':
    unittest.main()
