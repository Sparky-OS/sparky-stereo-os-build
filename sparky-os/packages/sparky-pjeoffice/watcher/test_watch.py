#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""The watcher against a local HTTPS server standing in for CNJ and TRF3, with generated stand-ins for the ZIPs. No network beyond loopback.
Usage: test_watch.py WORKDIR [WATCH.py]   (WORKDIR is writable and empty; needs openssl)"""
import hashlib, http.server, json, os, ssl, subprocess, sys, threading
from pathlib import Path

work = Path(sys.argv[1]).resolve()
watch = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).with_name('watch.py')
tests = Path(__file__).resolve().parent.parent / 'tests'
work.mkdir(parents=True, exist_ok=True)
FAIL = []


def check(name, condition, detail=''):
    print(('PASS  ' if condition else 'FAIL  ') + name + ('' if condition else '   [%s]' % detail), flush=True)
    if not condition:
        FAIL.append(name)


def sh(*command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


sh('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(work / 'ca.key'), '-out', str(work / 'ca.crt'), '-days', '3', '-subj', '/CN=pj18-watch-ca', '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
sh('openssl', 'req', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(work / 'srv.key'), '-out', str(work / 'srv.csr'), '-subj', '/CN=localhost')
(work / 'san.ext').write_text('subjectAltName=DNS:localhost,IP:127.0.0.1\n')
sh('openssl', 'x509', '-req', '-in', str(work / 'srv.csr'), '-CA', str(work / 'ca.crt'), '-CAkey', str(work / 'ca.key'), '-CAcreateserial', '-out', str(work / 'srv.crt'), '-days', '3', '-extfile', str(work / 'san.ext'))
www = work / 'www'
for version in ('2.5.90u', '2.5.91u'):
    sh(sys.executable, str(tests / 'make-fixture.py'), str(www), version)
zips = {v: (www / ('pjeoffice-pro-v%s-linux_x64.zip' % v)).read_bytes() for v in ('2.5.90u', '2.5.91u')}
state = {'guide': '2.5.90u', 'mode': 'normal', 'hits': 0, 'meta': None}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/guide.html':
            if state['guide'] is None:
                body = b'<html><body>no download here</body></html>'
            else:
                v = state['guide']
                body = ('<html><body><a href="https://localhost:%d/pjeoffice-pro-v%s-linux_x64.zip">Linux</a></body></html>' % (port, v)).encode()
            self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body); return
        if self.path == '/update.properties':
            body = b'app.version=2.5.90\n'
            self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body); return
        name = self.path.lstrip('/')
        found = [v for v in zips if name == 'pjeoffice-pro-v%s-linux_x64.zip' % v]
        if not found:
            self.send_error(404); return
        data = zips[found[0]]
        state['hits'] += 1
        if state['mode'] == 'differs' and state['hits'] % 2 == 0:
            data = data + b'\0'
        self.send_response(200)
        self.send_header('Content-Length', str(len(data) + (500 if state['mode'] == 'short' else 0)))
        if state['meta']:
            self.send_header('x-amz-meta-sha256', state['meta'])
        self.end_headers()
        self.wfile.write(data)
        self.wfile.flush()

    def log_message(self, *unused):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
port = server.server_address[1]
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(str(work / 'srv.crt'), str(work / 'srv.key'))
server.socket = context.wrap_socket(server.socket, server_side=True)
threading.Thread(target=server.serve_forever, daemon=True).start()
env = dict(os.environ, SSL_CERT_FILE=str(work / 'ca.crt'))
catalogue = www / 'catalogue-2.5.90u.json'
catalogue_hash = hashlib.sha256(catalogue.read_bytes()).hexdigest()
c = json.loads(catalogue.read_text())
c['versions']['2.5.90u']['url'] = 'https://localhost:%d/pjeoffice-pro-v2.5.90u-linux_x64.zip' % port
catalogue.write_text(json.dumps(c))
catalogue_hash = hashlib.sha256(catalogue.read_bytes()).hexdigest()


def watcher(tag, *extra, guide='guide.html'):
    folder = work / tag
    return sh(sys.executable, str(watch), '--catalogue', str(catalogue), '--workdir', str(folder), '--guide-url', 'https://localhost:%d/%s' % (port, guide),
              '--update-url', 'https://localhost:%d/update.properties' % port, '--proposal', str(work / (tag + '-proposal.json')), *extra, env=env)


print('== the published version is the reviewed one')
state.update(guide='2.5.90u', mode='normal', hits=0)
r = watcher('same')
check('exit 0', r.returncode == 0, r.stderr + r.stdout[-300:])
check('the report says it is the reviewed file', json.loads(r.stdout)['same_as_reviewed'] is True)
check('no proposal is written', not (work / 'same-proposal.json').exists())
check('the file was fetched twice, into two folders', len(list((work / 'same').glob('*/*/*.zip'))) == 2)
check('the update address version is reported (2.5.90 for 2.5.90u)', json.loads(r.stdout)['update_properties_version'] == '2.5.90')

print('== a new version, alike twice, becomes a proposal for a person to review')
state.update(guide='2.5.91u', mode='normal', hits=0)
r = watcher('new')
check('exit 3', r.returncode == 3, r.stderr + r.stdout[-300:])
proposal = json.loads((work / 'new-proposal.json').read_text())
want = hashlib.sha256(zips['2.5.91u']).hexdigest()
check('the proposal names the new version', proposal['current'] == '2.5.91u')
check('with the SHA-256 and size of the file as fetched', proposal['versions']['2.5.91u']['sha256'] == want and proposal['versions']['2.5.91u']['size'] == len(zips['2.5.91u']))
check('marked not reviewed', proposal['versions']['2.5.91u']['reviewed'].startswith('NOT REVIEWED'))
check('the reviewed entry is kept in the proposal', '2.5.90u' in proposal['versions'])
check('the catalogue itself is untouched', hashlib.sha256(catalogue.read_bytes()).hexdigest() == catalogue_hash)
facts = json.loads(r.stdout)['facts']
check('the reviewer is shown the bundled Java and the updater settings', 'jre_release' in facts and 'update_properties' in facts and facts['has']['pjeoffice-pro.jar'])

print("== the server's own metadata digest is a fact, never trust")
state.update(guide='2.5.91u', mode='normal', hits=0, meta='f' * 64)
r = watcher('meta')
check('a metadata digest that disagrees is reported', json.loads(r.stdout)['server_metadata_agrees'] is False and r.returncode == 3)
state['meta'] = None

print('== two fetches that differ propose nothing')
state.update(guide='2.5.91u', mode='differs', hits=0)
r = watcher('differs')
check('exit 2', r.returncode == 2, r.stderr)
check('it says the fetches differ', 'the two fetches differ' in r.stderr)
check('no proposal is written', not (work / 'differs-proposal.json').exists())

print('== a short body is not a file')
state.update(guide='2.5.91u', mode='short', hits=0)
r = watcher('short')
check('exit 1 or 2, nothing proposed', r.returncode in (1, 2) and not (work / 'short-proposal.json').exists(), r.stderr)

print('== the reviewed version label with another file is a disagreement')
state.update(guide='2.5.90u', mode='differs', hits=1)   # the first fetch is the plain file, the second has a byte more
r = watcher('label')
check('exit 2', r.returncode == 2, r.stderr)
state['mode'] = 'normal'
zips['2.5.90u'], saved = zips['2.5.90u'] + b'\0', zips['2.5.90u']
state['hits'] = 0
r = watcher('label2')
check('same label, another file: exit 2 and it names both digests', r.returncode == 2 and 'is not the reviewed one' in r.stderr, r.stderr)
zips['2.5.90u'] = saved

print('== a guide without the link, and an address that is not https')
state['guide'] = None
r = watcher('nolink')
check('no link: exit 1, said', r.returncode == 1 and 'names no Linux x64 file' in r.stderr, r.stderr)
state['guide'] = '2.5.90u'
r = sh(sys.executable, str(watch), '--catalogue', str(catalogue), '--workdir', str(work / 'plain'), '--guide-url', 'http://localhost:%d/guide.html' % port, env=env)
check('a plain http address is refused', r.returncode == 1 and 'not an https address' in r.stderr, r.stderr)
print()
print('RESULT: ' + ('FAIL' if FAIL else 'PASS'))
sys.exit(1 if FAIL else 0)
