#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
"""The chosen Graphics identity and its real NVIDIA environment reach the backend."""
import importlib.util
import os
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

path=Path(sys.argv.pop(1)) if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'debian/launch.py'
sys.modules['sparky_install_downloads']=types.SimpleNamespace(language=lambda:'en')
spec=importlib.util.spec_from_file_location('launcher',path)
launcher=importlib.util.module_from_spec(spec);spec.loader.exec_module(launcher)
GPU='pci-0000:01:00.0'

class Launched(Exception):pass
class Launcher(unittest.TestCase):
    def test_real_nvidia_key_and_one_stable_identity(self):
        graphics='__VK_LAYER_NV_optimus=NVIDIA_only\n__GLX_VENDOR_LIBRARY_NAME=nvidia\n'
        with patch.object(sys,'argv',['spirula-studio','our-model.ply']), patch.dict(os.environ,{'CUDA_VISIBLE_DEVICES':'7','DRI_PRIME':'wrong'},clear=True), patch.object(Path,'is_file',return_value=True), patch.object(launcher.subprocess,'check_output',side_effect=[GPU+'\n',graphics]) as query, patch.object(launcher.os,'execve',side_effect=Launched) as execute:
            with self.assertRaises(Launched):launcher.main()
        self.assertIn(['--choice',GPU,'--3d','--print','env'],[call.args[0][-5:] for call in query.call_args_list])
        binary,args,env=execute.call_args.args
        self.assertEqual(binary,'/usr/lib/spirula-studio/vulkan/spirula')
        self.assertEqual(args,[binary,'our-model.ply'])
        self.assertEqual(env['__VK_LAYER_NV_optimus'],'NVIDIA_only')
        self.assertEqual(env['SS_EDITION_GPU_PCI'],GPU)
        self.assertNotIn('CUDA_VISIBLE_DEVICES',env)
        self.assertNotIn('DRI_PRIME',env)

    def test_malformed_environment_name_never_executes(self):
        with patch.object(sys,'argv',['spirula-studio']), patch.object(Path,'is_file',return_value=True), patch.object(launcher.subprocess,'check_output',side_effect=[GPU+'\n','bad-key=value\n']), patch.object(launcher.os,'execve') as execute:
            with self.assertRaises(ValueError):launcher.main()
        execute.assert_not_called()

    def test_unresolved_identity_is_said_without_starting(self):
        with patch.object(sys,'argv',['spirula-studio']), patch.object(Path,'is_file',return_value=True), patch.object(launcher.subprocess,'check_output',return_value='unresolved\n'), patch.object(launcher,'say') as say, patch.object(launcher.os,'execve') as execute:
            self.assertEqual(launcher.main(),1)
        say.assert_called_once_with('graphics');execute.assert_not_called()

if __name__=='__main__':unittest.main()
