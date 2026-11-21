#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# A stand-in for Ollama's model registry on this computer, for proofs that download nothing real: it answers the registry's
# own two calls (GET /v2/NAMESPACE/MODEL/manifests/TAG with Docker's manifest v2, and GET .../blobs/sha256:DIGEST) for one
# model, standin:tiny, whose layers are a few kilobytes of fixed bytes. It is not a model: nothing can run it.
# Usage: standin-registry.py PORT   (prints "ready SIZE" when it listens; SIZE is the manifest's layers and config in bytes)
import hashlib
import http.server
import json
import sys

layers = {'application/vnd.ollama.image.model': b'standin-model ' * 300, 'application/vnd.ollama.image.license': b'Not a model: a test blob.\n'}
config = json.dumps({'model_format': 'gguf', 'model_family': 'standin', 'file_type': 'none'}).encode()
blobs = {hashlib.sha256(data).hexdigest(): data for data in list(layers.values()) + [config]}
manifest = json.dumps({'schemaVersion': 2, 'mediaType': 'application/vnd.docker.distribution.manifest.v2+json',
                       'config': {'mediaType': 'application/vnd.docker.container.image.v1+json', 'digest': 'sha256:' + hashlib.sha256(config).hexdigest(), 'size': len(config)},
                       'layers': [{'mediaType': kind, 'digest': 'sha256:' + hashlib.sha256(data).hexdigest(), 'size': len(data)} for kind, data in layers.items()]}).encode()
SIZE = len(config) + sum(len(d) for d in layers.values())


class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.do_GET(body=False)

    def do_GET(self, body=True):
        parts = self.path.split('/')
        if len(parts) == 6 and parts[1] == 'v2' and parts[4] == 'manifests' and parts[3] == 'standin' and parts[5] == 'tiny':
            data, kind = manifest, 'application/vnd.docker.distribution.manifest.v2+json'
        elif len(parts) == 6 and parts[1] == 'v2' and parts[4] == 'blobs' and parts[5].startswith('sha256:') and parts[5][7:] in blobs:
            data, kind = blobs[parts[5][7:]], 'application/octet-stream'
        else:
            self.send_error(404, 'not in the stand-in registry')
            return
        self.send_response(200)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        if body:
            self.wfile.write(data)

    def log_message(self, *args):
        sys.stderr.write('standin-registry: %s\n' % (args[0] % args[1:]))


server = http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), Handler)
print('ready', SIZE, flush=True)
server.serve_forever()
