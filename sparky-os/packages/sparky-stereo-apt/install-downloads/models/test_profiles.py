#!/usr/bin/python3
"""Root-only integration tests with our own bytes behind a local TLS owner fixture."""
import contextlib
import copy
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.request

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
spec = importlib.util.spec_from_file_location('model_profiles',HERE/'profilectl.py')
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)

BODY = b'Our generated model-profile fixture, without third-party weights.\n'
requests = []
class Owner(BaseHTTPRequestHandler):
    def log_message(self,*args):
        pass
    def do_HEAD(self):
        requests.append(('HEAD',self.path))
        self.send_response(200)
        self.send_header('Content-Length',str(len(BODY)))
        self.end_headers()
    def do_GET(self):
        requests.append(('GET',self.path))
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location','http://127.0.0.1/forbidden')
            self.end_headers()
            return
        self.send_response(200)
        self.send_header('Content-Length',str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY if self.path != '/wrong' else bytes([BODY[0]^1])+BODY[1:])

class Profiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.geteuid() != 0:
            raise RuntimeError('Run in a disposable root container')
        cls.home = Path(tempfile.mkdtemp(prefix='sp501-',dir='/var/lib'))
        cert,key = cls.home/'cert.pem',cls.home/'key.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=localhost',
                        '-addext','subjectAltName=IP:127.0.0.1','-keyout',str(key),'-out',str(cert)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        cls.server = HTTPServer(('127.0.0.1',0),Owner)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(cert,key)
        cls.server.socket = tls.wrap_socket(cls.server.socket,server_side=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever)
        cls.thread.start()
        engine.opener = urllib.request.build_opener(engine.HttpsRedirect(),urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=str(cert))))
        cls.url = 'https://127.0.0.1:'+str(cls.server.server_port)
        engine.notice.LANGDIR = str(HERE.parent/'lang')
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown();cls.thread.join();cls.server.server_close()
        shutil.rmtree(cls.home)
    def setUp(self):
        self.case = self.home/self._testMethodName
        self.case.mkdir()
        engine.DATA = self.case/'data';engine.DATA.mkdir()
        shutil.copy(HERE/'messages.json',engine.DATA/'messages.json')
        (engine.DATA/'licences').mkdir()
        (engine.DATA/'licences'/'fixture.txt').write_text('Our fixture: use permitted.\n')
        (engine.DATA/'profiles').mkdir()
        engine.STATE = self.case/'state'
        self.profile = dict(package='sp501-fixture-a',id='fixture-a',title='Fixture',root=str(self.case/'models'),
             files=[dict(file='shared.bin',url=self.url+'/good',bytes=len(BODY),sha256=hashlib.sha256(BODY).hexdigest())],
             download_bytes=len(BODY),version='1',group='sp501-fixture',consent_required=False,
             licences=[dict(name='Fixture',url=self.url+'/licence',file='fixture.txt')])
        requests.clear()
    def install(self,p=None,consent=False):
        with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
            return engine.install(p or self.profile,consent)
    def test_no_consent_makes_no_request(self):
        self.profile['consent_required']=True
        self.assertEqual(self.install(),1)
        self.assertEqual(requests,[])
        self.assertFalse(Path(self.profile['root']).exists())
    def test_wrong_hash_commits_nothing_and_retry_verifies(self):
        self.profile['files'][0]['url']=self.url+'/wrong'
        with self.assertRaises(ValueError):self.install()
        self.assertFalse((Path(self.profile['root'])/'shared.bin').exists())
        self.assertEqual(list(Path(self.profile['root']).glob('.model-install-*')),[])
        self.profile['files'][0]['url']=self.url+'/good'
        self.assertEqual(self.install(),0)
        requests.clear()
        self.assertEqual(self.install(),0)
        self.assertEqual(requests,[])
    def test_multi_file_failure_keeps_previous_bytes(self):
        self.assertEqual(self.install(),0)
        old=Path(self.profile['root'])/'shared.bin'
        p=copy.deepcopy(self.profile)
        p['files'].append(dict(p['files'][0],file='second.bin',url=self.url+'/wrong'))
        p['download_bytes']*=2
        with self.assertRaises(ValueError):self.install(p)
        self.assertEqual(old.read_bytes(),BODY)
        self.assertFalse((old.parent/'second.bin').exists())
    def test_purge_reference_counts_and_keeps_person_files(self):
        self.assertEqual(self.install(),0)
        other=dict(self.profile,package='sp501-fixture-b')
        self.assertEqual(self.install(other),0)
        root=Path(self.profile['root']);(root/'person.txt').write_text('keep')
        with contextlib.redirect_stdout(io.StringIO()):engine.purge(self.profile['package'])
        self.assertTrue((root/'shared.bin').exists())
        with contextlib.redirect_stdout(io.StringIO()):engine.purge(other['package'])
        self.assertFalse((root/'shared.bin').exists())
        self.assertEqual((root/'person.txt').read_text(),'keep')
    def test_symbolic_link_parent_refused_before_transfer(self):
        root=Path(self.profile['root']);root.symlink_to(self.case/'outside')
        with self.assertRaises(ValueError):self.install()
        self.assertEqual(requests,[])
    def test_preexisting_verified_person_file_is_not_adopted(self):
        root=Path(self.profile['root']);root.mkdir()
        (root/'shared.bin').write_bytes(BODY)
        self.assertEqual(self.install(),0)
        with contextlib.redirect_stdout(io.StringIO()):engine.purge(self.profile['package'])
        self.assertEqual((root/'shared.bin').read_bytes(),BODY)
    def test_preexisting_different_person_file_is_not_replaced(self):
        root=Path(self.profile['root']);root.mkdir()
        (root/'shared.bin').write_text('the person keeps this')
        with self.assertRaises(PermissionError):self.install()
        self.assertEqual(requests,[])
        self.assertEqual((root/'shared.bin').read_text(),'the person keeps this')
    def test_http_redirect_refused(self):
        self.profile['files'][0]['url']=self.url+'/redirect'
        with self.assertRaises(ValueError):self.install()
        self.assertFalse((Path(self.profile['root'])/'shared.bin').exists())
    def test_postprocess_failure_remains_owned_for_purge(self):
        self.profile['postprocess']=['/bin/false']
        with self.assertRaises(subprocess.CalledProcessError):self.install()
        root=Path(self.profile['root'])
        self.assertTrue((root/'shared.bin').exists())
        self.assertTrue((engine.STATE/'receipts'/('sp501-fixture-a.json')).exists())
        with contextlib.redirect_stdout(io.StringIO()):engine.purge(self.profile['package'])
        self.assertFalse((root/'shared.bin').exists())
    def test_profile_traversal_rejected(self):
        p=copy.deepcopy(self.profile);p['files'][0]['file']='../escape'
        (engine.DATA/'profiles'/'sp501-fixture-a.json').write_text(json.dumps(p))
        with self.assertRaises(ValueError):engine.profile('sp501-fixture-a')
    def test_metered_notice_and_ten_languages(self):
        texts=json.loads((HERE/'messages.json').read_text())
        self.assertEqual(set(texts),{'en','pl','pt_BR','fr','de','es','ja','ko','zh_CN','zh_TW'})
        for code in texts:
            with unittest.mock.patch.dict(os.environ,{'LC_ALL':code+'.UTF-8'}):
                self.assertIn('2997',engine.words('plan',profile='Fixture',size='2997 B'))
                report=engine.notice.assess([dict(package='sp501-fixture-a',version='1',size=len(BODY),source=self.url)],state=('yes','yes'))
                self.assertTrue(report['announce']);self.assertEqual(report['state'],'yes')
                self.assertIn(self.url,'\n'.join(report['text']))

if __name__ == '__main__':
    import unittest.mock
    unittest.main(verbosity=2)
