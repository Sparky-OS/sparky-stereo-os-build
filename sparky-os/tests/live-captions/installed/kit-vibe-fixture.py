#!/usr/bin/python3
"""Strict HTTP boundary stand-in. No inference engine or model reader."""
import http.server,json,sys
from pathlib import Path
model=None
class Handler(http.server.BaseHTTPRequestHandler):
 def reply(self,value):
  body=json.dumps(value).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 def do_GET(self):
  if self.path=='/v1/models':self.reply({'data':[{'id':Path(model).name}] if model else []})
  elif self.path=='/health':self.reply({'status':'ok'})
  else:self.send_error(404)
 def do_POST(self):
  global model
  body=self.rfile.read(int(self.headers['Content-Length']))
  if self.path=='/v1/models/load':
   value=json.loads(body)
   if set(value)!={'path','gpu_device','no_gpu'} or not value['no_gpu']:self.send_error(400);return
   model=value['path'];self.reply({'status':'loaded','model':Path(model).name})
  elif self.path=='/v1/audio/transcriptions':
   if not model or b'name="file"; filename="fox.wav"' not in body or b'RIFF' not in body:self.send_error(400);return
   self.reply({'text':'The quick brown fox jumps over the lazy dog.'})
  else:self.send_error(404)
 def do_DELETE(self):
  global model
  model=None;self.reply({'status':'unloaded'})
server=http.server.HTTPServer(('127.0.0.1',0),Handler)
print(json.dumps({'status':'ready','port':server.server_port}),flush=True)
server.serve_forever()
