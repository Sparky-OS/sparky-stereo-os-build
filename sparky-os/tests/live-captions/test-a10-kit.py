#!/usr/bin/python3
"""Model-free negative controls for the bench kit; only in the proof container."""
import contextlib,importlib.util,io,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
root=Path(__file__).parent

def load(name,file):
 spec=importlib.util.spec_from_file_location(name,root/file);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
kit=load('kit','a10-kit.py');live=load('live','a10-live.py')
class Mechanics(unittest.TestCase):
 def test_words_not_any_caption(self):
  self.assertFalse(live.known(''));self.assertFalse(live.known('A caption appeared.'));self.assertFalse(live.known('The quick brown fox.'))
  self.assertTrue(live.known('The quick brown fox jumps over the lazy dog.'))
 def test_hwmon_without_thermal_zones(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'hwmon0';p.mkdir();(p/'name').write_text('k10temp\n');(p/'temp1_input').write_text('42000\n')
   self.assertEqual(live.temperature(Path(d))['celsius'],42)
   (p/'temp1_input').unlink();self.assertIsNone(live.temperature(Path(d))['celsius']);self.assertIn('unavailable',live.temperature(Path(d))['warning'])
 def test_package_change_refused(self):
  for plan in ['Inst old [1] (2 repo)\n','Remv old [1]\n','Inst old (1 repo)\n']:
   for state in ('installed','config-files'):
    with self.assertRaises(RuntimeError):kit.safe_additions(plan,{'old:amd64':('1',state)})
  self.assertEqual(kit.safe_additions('Inst new (1 repo)\n',{}),['new'])
 def test_download_offered_and_verified(self):
  data=b'synthetic download witness; never a model';item=dict(url='https://fixture.invalid/witness',bytes=len(data),sha256=__import__('hashlib').sha256(data).hexdigest())
  with tempfile.TemporaryDirectory() as d:
   messages=io.StringIO()
   def opened(*args,**kw):
    self.assertIn(item['sha256'],messages.getvalue());self.assertIn(str(len(data)),messages.getvalue());return io.BytesIO(data)
   with contextlib.redirect_stdout(messages),patch.object(kit.HTTP,'open',side_effect=opened):kit.fetch(item,Path(d)/'witness')
   self.assertEqual((Path(d)/'witness').read_bytes(),data)
   for bad in [dict(item,bytes=len(data)-1),dict(item,sha256='0'*64)]:
    with patch.object(kit.HTTP,'open',return_value=io.BytesIO(data)),self.assertRaises(ValueError):kit.fetch(bad,Path(d)/('bad-'+str(bad['bytes'])))
 def test_multipart_real_field(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'fox.wav';p.write_bytes(b'RIFF synthetic')
   data,content=live.multipart(p);self.assertIn(b'name="file"; filename="fox.wav"',data);self.assertIn(b'RIFF synthetic',data);self.assertIn('boundary=',content);self.assertIn(b'name="n_threads"',data);self.assertNotIn(b'name="threads"',data)
if __name__=='__main__':unittest.main()
