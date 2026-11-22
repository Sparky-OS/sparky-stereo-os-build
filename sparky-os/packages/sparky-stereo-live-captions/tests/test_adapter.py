#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Model-free adapter controls: synthetic bytes and a Unix-socket peer only."""
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('adapter', str(HERE / 'bin/sparky-stereo-live-captions'))
a = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(a)

# This peer has no recognition code and cannot open a microphone or model.
PEER = '''import json,os,signal,socket,sys,time
s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1]);s.listen(1)
c,_=s.accept();c.sendall(b'{"type":"hello","proto":1,"daemon":"captiond"}\\n')
e=dict(type='status',state='listening',gpu=True,accelerator='Test Vulkan',behind=False)
if sys.argv[2]=='mismatch': e.update(gpu=False,accelerator='Test CPU')
for behind in [False,True,False]:
 e['behind']=behind;c.sendall((json.dumps(e)+'\\n').encode());time.sleep(.15)
if sys.argv[2]!='mismatch':os.kill(int(sys.argv[3]),signal.SIGTERM)
time.sleep(30)
'''


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.env = patch.dict(os.environ, dict(XDG_DATA_HOME=str(self.root/'data'),
                         XDG_STATE_HOME=str(self.root/'state'), XDG_RUNTIME_DIR=str(self.root), LANG='en_US.UTF-8', LC_ALL=''))
        self.env.start()
        self.settings = {}
        settings = self.settings
        api = types.SimpleNamespace(problems=None, held=lambda even: not even,
                  Settings=lambda: types.SimpleNamespace(get=lambda g,k,d=None: settings.get((tuple(g),k),d)),
                  write=lambda g,k,v: settings.__setitem__((tuple(g),k),v))
        self.api = patch.object(a, 'partners', lambda: api); self.api.start()
        self.oldshare, self.oldpresets = a.SHARE, a.PRESETS
        a.SHARE = self.root/'share';a.SHARE.mkdir()
        (a.SHARE/'lang').symlink_to(HERE/'lang', target_is_directory=True)
        a.PRESETS = self.root/'presets';a.PRESETS.mkdir()
        self.seed = {'model.gpuDevice': None, 'analytics_enabled': False, 'custom': {'keep': [1,2]}}
        for name in ('default','light','basic'):(a.PRESETS/(name+'.json')).write_text(json.dumps(self.seed))
        data = b'Fixture text. This is not a speech recognition model.\n'
        self.entry = dict(id='tiny',file='ggml-tiny.bin',bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),url='https://invalid.example/fixture')
        (a.SHARE/'models.json').write_text(json.dumps([self.entry]))
        self.model = a.model_path(self.entry);self.model.parent.mkdir(parents=True);self.model.write_bytes(data)
        self.idle = patch.object(a, 'running', lambda name: False);self.idle.start()
        self.unit = patch.object(a, 'unit', lambda *args,**kw: types.SimpleNamespace(returncode=1));self.unit.start()

    def tearDown(self):
        self.unit.stop();self.idle.stop();self.api.stop();self.env.stop()
        a.SHARE,self.oldshare = self.oldshare,a.SHARE
        a.PRESETS = self.oldpresets
        self.tmp.cleanup()

    def test_new_store_shared_path_no_copy(self):
        a.select('tiny')
        target,record,before,contents = a.vibe_plan(self.model)
        saved=json.loads(target.read_text())
        self.assertEqual(saved['custom'],self.seed['custom'])
        self.assertEqual(saved['model.path'],str(self.model))
        self.assertEqual(saved['models_folder'],str(self.model.parent))
        self.assertEqual(a.chosen()['path'],str(self.model))
        self.assertEqual(self.model.stat().st_nlink,1)
        self.assertEqual(len(list(self.root.rglob('*.bin'))),1)

    def test_existing_library_stays_in_place(self):
        outside=self.root/'old-library'/self.entry['file'];outside.parent.mkdir();self.model.rename(outside)
        a.select(str(outside))
        self.assertEqual(a.verify_model(a.chosen()),outside)
        self.assertFalse(self.model.exists())

    def test_known_seed_preserves_unrelated_values(self):
        target=a.data_home()/'github.com.thewh1teagle.vibe/app_config.json'
        target.parent.mkdir();target.write_text(json.dumps(dict(self.seed,**{'model.gpuDevice':2})))
        a.select('tiny');saved=json.loads(target.read_text())
        self.assertEqual(saved['model.gpuDevice'],2);self.assertEqual(saved['custom'],self.seed['custom'])

    def test_unknown_and_changed_store_refused(self):
        target=a.data_home()/'github.com.thewh1teagle.vibe/app_config.json'
        target.parent.mkdir();target.write_text('{"personal":"keep"}')
        with self.assertRaises(a.Refused):a.select('tiny')
        self.assertEqual(target.read_text(),'{"personal":"keep"}')
        target.unlink();a.select('tiny');target.write_text('{"changed":true}')
        with self.assertRaises(a.Refused):a.select('tiny')
        self.assertEqual(target.read_text(),'{"changed":true}')

    def test_exclusive_publication_and_symlink(self):
        target=self.root/'receipt';target.write_bytes(b'personal')
        with self.assertRaises(a.Refused):a.publish(target,b'new')
        link=self.root/'link';link.symlink_to(target)
        with self.assertRaises(a.Refused):a.publish(link,b'new')
        self.assertEqual(target.read_bytes(),b'personal')
        target.unlink();original=os.link
        def race(src,dest):
            Path(dest).write_bytes(b'created by app');original(src,dest)
        with patch.object(os,'link',race),self.assertRaises(a.Refused):a.publish(target,b'new')
        self.assertEqual(target.read_bytes(),b'created by app')

    def test_changed_model_refused(self):
        self.model.write_bytes(b'changed')
        with self.assertRaises(a.Refused):a.select('tiny')
        self.assertEqual(self.model.read_bytes(),b'changed')

    def test_running_app_refused(self):
        with patch.object(a,'running',lambda name: name=='vibe'),self.assertRaises(a.Refused):a.select('tiny')
        self.assertFalse((a.data_home()/'github.com.thewh1teagle.vibe/app_config.json').exists())

    def test_metered_does_not_fetch(self):
        self.model.unlink()
        with patch.object(a.urllib.request,'build_opener') as opener,self.assertRaises(a.Refused):a.download(self.entry)
        opener.assert_not_called();self.assertFalse(self.model.exists())

    def test_download_checksum_and_size_and_racing_file(self):
        data=self.model.read_bytes();self.model.unlink()
        for payload in [data+b'extra',data[:-1],b'x'*len(data)]:
            response=io.BytesIO(payload)
            with patch.object(a.urllib.request,'build_opener',lambda *x: types.SimpleNamespace(open=lambda *x,**kw:response)):
                with self.assertRaises(a.Refused):a.download(self.entry,True)
            self.assertFalse(self.model.exists())
        with patch.object(a.urllib.request,'build_opener',lambda *x: types.SimpleNamespace(open=lambda *x,**kw:io.BytesIO(data))):
            a.download(self.entry,True)
        self.assertEqual(self.model.read_bytes(),data)
        self.assertFalse(list(self.model.parent.glob('.download-*')))

    def test_inherited_captiond_settings_removed(self):
        with patch.dict(os.environ,{'CAPTIOND_INPUT':'auto-source','CAPTIOND_GPU':'false'}):
            self.assertFalse(any(k.startswith('CAPTIOND_') for k in a.cleaned_env()))

    def session(self,mode,mic=False):
        a.select('tiny');self.settings[(('LiveCaptions',),'Microphone')]='true' if mic else 'false'
        children=[];notices=[];configs=[];environments=[];original=subprocess.Popen
        def launch(command,**kwargs):
            environments.append(kwargs['env'])
            if '/usr/bin/captiond' in command:
                configs.append(Path(command[command.index('--config')+1]).read_text())
                sock=command[command.index('--socket')+1]
                child=original([sys.executable,'-c',PEER,sock,mode,str(os.getpid())])
            else:
                self.assertEqual(command,['/usr/bin/kaption'])
                child=original([sys.executable,'-c','import time;time.sleep(30)'])
            children.append(child);return child
        with (patch.object(a,'gpu_route',lambda:dict(gpu=True,device=0,name='Test Vulkan')),
             patch.object(a,'notice',lambda key,*values,**kw:notices.append(key)),
             patch.object(a.subprocess,'Popen',launch)):
            if mode=='mismatch':
                with self.assertRaises(a.Refused) as error:a.serve()
                self.assertEqual(error.exception.key,'route')
            else:a.serve()
        self.assertTrue(all(child.poll() is not None for child in children))
        self.assertFalse(list(a.runtime().iterdir()))
        self.assertTrue(self.model.exists())
        self.assertIn('input='+('auto-source' if mic else 'off')+'\n',configs[0])
        self.assertIn('input_mix=false\n',configs[0])
        self.assertEqual(environments[0]['CAPTIOND_MODEL_PATH'],str(self.model.parent))
        return children,notices

    def test_pair_stops_and_measured_behind_recovers(self):
        children,notices=self.session('normal')
        self.assertEqual(len(children),2)
        self.assertEqual(notices,['waiting','actual','slow','actual','stopped'])

    def test_route_mismatch_stops_before_frontend(self):
        children,_=self.session('mismatch');self.assertEqual(len(children),1)

    def test_microphone_explicit(self):self.session('normal',True)

    def test_languages_and_pending_list(self):
        en=json.loads((HERE/'lang/en.json').read_text());pt=json.loads((HERE/'lang/pt_BR.json').read_text())
        self.assertEqual(set(en),set(pt))
        for key,text in en.items():
            import string
            fields=lambda s:[f for _,f,_,_ in string.Formatter().parse(s) if f is not None]
            self.assertEqual(fields(text),fields(pt[key]))
        rows=(HERE/'share/pending-translation.tsv').read_text().splitlines()[1:]
        self.assertEqual({r.split('\t')[0] for r in rows},set(en))


if __name__=='__main__':unittest.main(verbosity=2)
