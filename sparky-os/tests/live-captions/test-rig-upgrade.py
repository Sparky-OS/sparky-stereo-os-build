#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('plan',Path(__file__).with_name('check-rig-upgrade.py'));plan=importlib.util.module_from_spec(spec);spec.loader.exec_module(plan)
class Plans(unittest.TestCase):
    def test_complete_upgrade(self):
        self.assertEqual(plan.check(['Inst captiond [1] (2)','Inst qaption [1] (2)'],['captiond','qaption'])['Remv'],[])
    def test_removal_refused(self):
        with self.assertRaisesRegex(ValueError,'Remv qaption'):plan.check(['Remv qaption [1]','Inst captiond [1] (2)'],['captiond'])
    def test_unexpected_install_refused(self):
        with self.assertRaisesRegex(ValueError,'Unexpected Inst'):plan.check(['Inst captiond [1] (2)','Inst unrelated (1)'],['captiond'])
if __name__=='__main__':unittest.main()
