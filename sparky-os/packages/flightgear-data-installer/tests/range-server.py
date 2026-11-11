#!/usr/bin/python3
# A small HTTPS server for the parallel-download tests of flightgear-data-installer: serves one file with HTTP byte ranges.
# Usage: range-server.py PORT FILE MODE LOG CERT KEY
# MODE: normal   206 for every range
#       cut      the first answer for each range start sends only half of the bytes asked, then closes the connection
#       norange  ignores Range and always answers 200 with the whole file
#       slow     sends 64 KiB per second, so a run can be stopped half way
import http.server, ssl, sys, time, threading

port, path, mode, logp, cert, key = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
data = open(path, 'rb').read()
seen = set()
lock = threading.Lock()


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass

    def do_GET(self):
        rng = self.headers.get('Range')
        with lock:
            open(logp, 'a').write('%s %s\n' % (time.time(), rng))
        start, end = 0, len(data) - 1
        if rng and mode != 'norange':
            a, b = rng.split('=')[1].split('-')
            start, end = int(a), int(b) if b else len(data) - 1
            self.send_response(206)
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, len(data)))
        else:
            self.send_response(200)
        body = data[start:end + 1]
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Content-Type', 'application/x-xz')
        self.end_headers()
        if mode == 'cut':
            with lock:
                first = start not in seen
                seen.add(start)
            if first:
                self.wfile.write(body[:len(body) // 2])
                self.wfile.flush()
                self.close_connection = True
                self.connection.shutdown(2)
                return
        if mode == 'slow':
            for i in range(0, len(body), 65536):
                self.wfile.write(body[i:i + 65536])
                self.wfile.flush()
                time.sleep(1.0)
            return
        self.wfile.write(body)


s = http.server.ThreadingHTTPServer(('127.0.0.1', port), H)
c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
c.load_cert_chain(cert, key)
s.socket = c.wrap_socket(s.socket, server_side=True)
s.serve_forever()
