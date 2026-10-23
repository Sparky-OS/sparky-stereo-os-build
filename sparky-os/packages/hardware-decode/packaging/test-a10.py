#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('a10', Path(__file__).with_name('a10-matrix.py'))
a10=importlib.util.module_from_spec(spec)
spec.loader.exec_module(a10)

class A10(unittest.TestCase):
    def test_dry_run_cannot_call_commands_or_write(self):
        output=io.StringIO()
        with patch.object(sys, 'argv', ['a10-matrix.py', '--phase', 'after', '--host', 'unreachable', '--dry-run']), \
             patch.object(a10.subprocess, 'run', side_effect=AssertionError('subprocess')), \
             patch.object(a10.subprocess, 'Popen', side_effect=AssertionError('subprocess')), \
             patch.object(a10.subprocess, 'check_output', side_effect=AssertionError('subprocess')), \
             patch.object(Path, 'mkdir', side_effect=AssertionError('mkdir')), \
             patch.object(Path, 'open', side_effect=AssertionError('open')), \
             contextlib.redirect_stdout(output):
            a10.main()
        data=json.loads(output.getvalue())
        self.assertEqual(len(data['cases']),216)
        self.assertFalse(data['screens_changed'])
        self.assertFalse(data['packages_installed'])
        self.assertEqual({c['route'] for c in data['cases']},set(a10.ROUTES))
        self.assertEqual({c['api'] for c in data['cases']},set(a10.APIS))
        self.assertEqual({c['film'] for c in data['cases']},set(a10.FILMS))

    def test_exact_mode_names_and_missing_control(self):
        sample='Output: 1 eDP-1 enabled\n Modes: 0:1366x768@60.01*! 1:1366x768@60.01(virtual-3D:5)\nOutput: 2 HDMI-A-1 enabled\n Modes: 2:1920x1080@30.00* 3:1920x1080@30.00(3D-FP)\n'
        self.assertEqual(a10.mode_ids(sample),{'E2':'0','E3':'1','T2':'2','T3':'3'})
        with self.assertRaises(ValueError):
            a10.mode_ids(sample.replace('(3D-FP)',''))

    def test_restore_original_extended_geometry(self):
        snapshot={'outputs':[{'name':'eDP-1','enabled':True,'currentModeId':'31','pos':{'x':1920,'y':0},'scale':1.25,'id':1,'replicationSource':0}, {'name':'HDMI-A-1','enabled':True,'currentModeId':'21','pos':{'x':0,'y':0},'scale':1,'id':2,'replicationSource':0}]}
        args=a10.restore_args(snapshot)
        self.assertIn('output.eDP-1.mode.31',args)
        self.assertIn('output.eDP-1.position.1920,0',args)
        self.assertIn('output.eDP-1.scale.1.25',args)
        self.assertIn('output.HDMI-A-1.mirror.none',args)

    def test_execution_refuses_other_machine_before_commands(self):
        with patch.object(a10,'read',return_value='other computer'), patch.object(a10.subprocess,'run',side_effect=AssertionError('subprocess')):
            with self.assertRaisesRegex(ValueError,'A10 laptop'):
                a10.execute(None)

if __name__=='__main__':
    unittest.main()
