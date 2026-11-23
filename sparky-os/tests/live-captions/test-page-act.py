#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util,sys,types,unittest
from pathlib import Path
from unittest.mock import patch
fake=types.SimpleNamespace(Registry=types.SimpleNamespace(getDesktop=lambda _:None),STATE_ENABLED=1)
sys.modules['pyatspi']=fake
path=Path(__file__).with_name('page-act.py')
if not path.exists():path=Path(__file__).parent/'installed/page-act.py'
spec=importlib.util.spec_from_file_location('page_act',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class Control:
 name='Refresh';nActions=1
 def __init__(self,stale=None,activation_error=False):self.stale=stale;self.activation_error=activation_error;self.activations=0
 def getRoleName(self):return 'button'
 def getState(self):
  if self.stale=='state':self.stale=None;raise RuntimeError('stale state object')
  return types.SimpleNamespace(contains=lambda _:True)
 def queryAction(self):
  if self.stale=='action':self.stale=None;raise RuntimeError('stale action object')
  return self
 def getName(self,_):return 'Press'
 def doAction(self,_):
  self.activations+=1
  if self.activation_error:raise RuntimeError('activation reply lost')
  return True
class Tests(unittest.TestCase):
 def invoke(self,control):
  with patch.object(fake.Registry,'getDesktop',return_value=control),patch.object(module.time,'sleep'),patch.object(module.Atspi,'set_timeout') as timeout:
   result=module.main('Refresh')
   self.assertTrue(timeout.call_args_list)
   self.assertTrue(all(0<call.args[0]<=120000 and call.args[1]==0 for call in timeout.call_args_list))
   return result
 def test_stale_state(self):
  c=Control('state');self.assertEqual(self.invoke(c),0);self.assertEqual(c.activations,1)
 def test_stale_action(self):
  c=Control('action');self.assertEqual(self.invoke(c),0);self.assertEqual(c.activations,1)
 def test_lost_activation_reply_is_not_retried(self):
  c=Control(activation_error=True)
  with self.assertRaisesRegex(RuntimeError,'reply lost'):self.invoke(c)
  self.assertEqual(c.activations,1)
if __name__=='__main__':unittest.main()
