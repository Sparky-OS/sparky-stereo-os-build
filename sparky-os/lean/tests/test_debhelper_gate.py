# SPDX-License-Identifier: MIT
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, mock
from lean import debhelper

class GateInputs(TestCase):
    def test_missing_snapshot_removes_outputs(self):
        with TemporaryDirectory() as d:
            deb = Path(d) / 'runtime_1_amd64.deb'
            deb.touch()
            with mock.patch.dict('os.environ', {'SPARKY_LC_SIBLINGS_FILE': d + '/missing'}):
                with self.assertRaises(FileNotFoundError):
                    debhelper.link_gate([deb])
            self.assertFalse(deb.exists())

    def test_native_gate_receives_cohort_and_floors(self):
        with TemporaryDirectory() as d:
            current, previous = Path(d) / 'current', Path(d) / 'previous'
            current.write_text('/cohort/engine.deb\n')
            previous.write_text('/published/engine.deb\n')
            env = {'SPARKY_LC_SIBLINGS_FILE': str(current),
                   'SPARKY_LC_PREVIOUS_SIBLINGS_FILE': str(previous),
                   'SPARKY_LC_MIN_FREE_GIB': '15', 'SPARKY_LC_ROOT_MIN_FREE_GIB': '15'}
            with mock.patch.dict('os.environ', env), mock.patch.object(debhelper.release, 'check_link') as check:
                debhelper.link_gate([Path('runtime_1_amd64.deb'), Path('runtime-dbgsym_1_amd64.deb')])
            self.assertEqual(check.call_args.args[0], [Path('runtime_1_amd64.deb')])
            self.assertEqual(check.call_args.kwargs['siblings'], ['/cohort/engine.deb'])
            self.assertEqual(check.call_args.kwargs['previous_siblings'], ['/published/engine.deb'])
            self.assertEqual(check.call_args.kwargs['root_min_free_gib'], 15)
