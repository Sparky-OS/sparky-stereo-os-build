#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""A small HTTPS file server with byte ranges for the installer's tests. Usage: serve.py DIR CERT KEY PORT [--cut-at BYTES]
--cut-at closes the connection after that many bytes of a first, whole-file request (an interrupted download); a ranged
request (a resumed one) is served in full."""
import http.server, os, re, ssl, sys
from pathlib import Path

root, cert, key, port = Path(sys.argv[1]), sys.argv[2], sys.argv[3], int(sys.argv[4])
cut = int(sys.argv[sys.argv.index('--cut-at') + 1]) if '--cut-at' in sys.argv else None


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = root / self.path.lstrip('/').split('?')[0]
        if not path.is_file():
            self.send_error(404)
            return
        data = path.read_bytes()
        start, status = 0, 200
        found = re.match(r'bytes=(\d+)-', self.headers.get('Range', ''))
        if found:
            start, status = int(found.group(1)), 206
        body = data[start:]
        self.send_response(status)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Accept-Ranges', 'bytes')
        if status == 206:
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, len(data) - 1, len(data)))
        self.end_headers()
        if cut is not None and status == 200 and len(data) > cut:
            self.wfile.write(body[:cut])
            self.wfile.flush()
            self.connection.shutdown(2)
            return
        self.wfile.write(body)

    def log_message(self, *unused):
        pass


server = http.server.ThreadingHTTPServer(('0.0.0.0', port), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
server.socket = context.wrap_socket(server.socket, server_side=True)
print('serving', root, 'on', port, flush=True)
server.serve_forever()
