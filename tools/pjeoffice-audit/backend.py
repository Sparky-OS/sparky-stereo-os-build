# SPDX-License-Identifier: GPL-3.0-or-later
from http.server import BaseHTTPRequestHandler,HTTPServer
from pathlib import Path
import json
class Handler(BaseHTTPRequestHandler):
 def do_POST(self):
  body=self.rfile.read(int(self.headers.get('Content-Length',0)))
  n=len(list(Path('/scratch').glob('callback-*.body')))
  Path(f'/scratch/callback-{n}.body').write_bytes(body)
  Path(f'/scratch/callback-{n}.json').write_text(json.dumps({'path':self.path,'headers':dict(self.headers)}))
  self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(b'{"success":true}')
 def log_message(self,*args): pass
HTTPServer(('127.0.0.1',18818),Handler).serve_forever()
