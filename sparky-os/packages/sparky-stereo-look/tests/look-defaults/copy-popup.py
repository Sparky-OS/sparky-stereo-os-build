#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Observe a real KIO copy and its native popup while the job is still running."""
import http.server
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import threading
import time

case = Path(os.environ['CASE'])
stop = threading.Event()


class SlowFile(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(200)
        self.send_header('Content-Length', str(64 * 1024 * 1024))
        self.send_header('Content-Type', 'application/octet-stream')
        self.end_headers()

    def do_GET(self):
        self.do_HEAD()
        try:
            for _ in range(1024):
                if stop.is_set():
                    break
                self.wfile.write(b'x' * 65536)
                self.wfile.flush()
                time.sleep(0.1)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *args):
        pass


def windows():
    active = {}
    for line in (case / 'session.log').read_text(errors='replace').splitlines():
        match = re.search(r'(ADDED|REMOVED) (?:org\.kde\.)?plasmashell type=(13|17) .* wid=(\S+)', line)
        if match:
            if match[1] == 'ADDED':
                active[match[3]] = line
            else:
                active.pop(match[3], None)
    return active


def job_paths():
    result = subprocess.run(['qdbus6', 'org.kde.JobViewServer'], text=True, capture_output=True)
    return [line.strip() for line in result.stdout.splitlines() if 'JobView_' in line]


def shot(label):
    subprocess.run(['python3', '/rig-scripts/login-splash/shot.py', 'Virtual-0', str(case / f'copy-{label}.png')], check=True)


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), SlowFile)
threading.Thread(target=server.serve_forever, daemon=True).start()
log = (case / 'copy-client.log').open('w')
initial = set(windows())
client = subprocess.Popen(['/test-bin/copy-file', f'http://127.0.0.1:{server.server_port}/ld668-proof.bin', str(case / 'copy-target.bin')], stdout=log, stderr=log, start_new_session=True)
try:
    time.sleep(3)
    early = dict(windows=sorted(set(windows()) - initial), jobPaths=job_paths(), running=client.poll() is None,
                 bytes=sum(p.stat().st_size for p in case.glob('copy-target*') if p.is_file()))
    shot('early')
    time.sleep(15)
    late = dict(windows=sorted(set(windows()) - initial), jobPaths=job_paths(), running=client.poll() is None,
                bytes=sum(p.stat().st_size for p in case.glob('copy-target*') if p.is_file()))
    shot('late')
    dismiss = os.environ.get('EXPECT_POPUP_DISMISS', '0') == '1'
    checks = dict(popupAppeared=bool(early['windows']),
                  popupBehavior=(not late['windows']) if dismiss else bool(late['windows']),
                  jobStillRegistered=bool(late['jobPaths']),
                  copyStillRunning=early['running'] and late['running'],
                  copyAdvances=late['bytes'] > early['bytes'] > 0)
    if dismiss and not late['windows']:
        with (case / 'tray-input.log').open('w') as input_log:
            pointer = subprocess.Popen(['/test-bin/fakeinput', 'm:1723,1051', 's:300', 'b:272', 's:300', 'm:1400,600', 's:5000'], stdout=input_log, stderr=input_log)
            try:
                time.sleep(2)
                shot('tray')
                late['trayJobPaths'] = job_paths()
                checks['jobRetainedWhenTrayOpened'] = bool(late['trayJobPaths'])
            finally:
                pointer.wait(timeout=6)
    (case / 'copy-popup.json').write_text(json.dumps(dict(early=early, late=late, expectDismiss=dismiss, checks=checks), indent=2) + '\n')
    for name, passed in checks.items():
        print('PASS' if passed else 'FAIL', name, flush=True)
    result = 0 if all(checks.values()) else 1
finally:
    stop.set()
    try:
        os.killpg(client.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    client.wait(timeout=5)
    server.shutdown()
    server.server_close()
    log.close()
    for p in case.glob('copy-target*'):
        if p.is_file(): p.unlink()
raise SystemExit(result)
