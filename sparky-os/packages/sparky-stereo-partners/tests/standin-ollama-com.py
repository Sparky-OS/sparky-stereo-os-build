#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
"""A stand-in for ollama.com's account routes, over TLS, for the Partners page's sign-in rows (ORDER 70). Nothing of the
real service is contacted: the test maps ollama.com to this server's address in /etc/hosts and trusts its own certificate
authority. It answers what Ollama 0.40.16's engine asks (api/client.go): POST /api/me (401 until the test links the key,
then an account), DELETE /api/user/keys/KEY (unlinks); every request is logged with whether it carried Ollama's signature.
    standin-ollama-com.py CERT KEY STATE LOG [ADDRESS]   (STATE holds "linked" or anything else; ADDRESS 127.0.0.4)
"""
import http.server
import json
import ssl
import sys

cert, key, state, log = sys.argv[1:5]
address = sys.argv[5] if len(sys.argv) > 5 else '127.0.0.4'


def linked():
    try:
        with open(state) as stream:
            return stream.read().strip() == 'linked'
    except OSError:
        return False


class Handler(http.server.BaseHTTPRequestHandler):
    def note(self):
        with open(log, 'a') as stream:
            stream.write('%s %s auth=%s\n' % (self.command, self.path.split('?')[0], 'yes' if self.headers.get('Authorization') else 'no'))

    def answer(self, code, body):
        data = json.dumps(body).encode() if body is not None else b''
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        self.note()
        length = int(self.headers.get('Content-Length') or 0)
        self.rfile.read(length)
        if self.path.split('?')[0] == '/api/me':
            if linked():
                self.answer(200, {'id': '00000000-0000-0000-0000-000000000001', 'name': 'tester', 'email': '', 'plan': 'free'})
            else:
                self.answer(401, {'error': 'unauthorized'})
            return
        self.answer(404, {'error': 'not found'})

    def do_DELETE(self):
        self.note()
        if self.path.startswith('/api/user/keys/'):
            with open(state, 'w') as stream:
                stream.write('unlinked\n')
            self.answer(200, None)
            return
        self.answer(404, {'error': 'not found'})

    def do_GET(self):
        self.note()
        self.answer(404, {'error': 'not found'})

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer((address, 443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
server.socket = context.wrap_socket(server.socket, server_side=True)
print('ready', flush=True)
server.serve_forever()
