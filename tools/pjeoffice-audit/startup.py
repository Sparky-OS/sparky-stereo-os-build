#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Measure an unchanged PJeOffice ZIP in an isolated, disposable container.

Arguments: application directory, Java executable, result directory, optional
Java arguments. Does not install, patch, sign, or contact a court service.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request
import urllib.error

app = Path(sys.argv[1]).resolve()
java = sys.argv[2]
out = Path(sys.argv[3]).resolve()
out.mkdir(parents=True, exist_ok=False)
home = out / 'home'
home.mkdir()
env = dict(os.environ, HOME=str(home), DISPLAY=':99')
env.pop('WAYLAND_DISPLAY', None)
commands = [java, *sys.argv[4:], '-XX:+UseG1GC', '-Xms20m', '-Xmx2048m',
            '-Duser.home=' + str(home), '-Dpjeoffice_home=' + str(app),
            '-Dffmpeg_home=' + str(app), '-Dpjeoffice_looksandfeels=Metal',
            '-Dcutplayer4j_looksandfeels=Nimbus', '-Dsigner4j_a3auto=true',
            '-jar', 'pjeoffice-pro.jar']
result = {'command': commands, 'http': {}, 'scope': 'Xvfb startup, no tray manager'}
with (out / 'java-version.txt').open('w') as f:
    subprocess.run([java, '-version'], stdout=f, stderr=subprocess.STDOUT, check=True)
with (out / 'xvfb.log').open('w') as xf, (out / 'application.log').open('w') as af:
    x = subprocess.Popen(['Xvfb', ':99', '-screen', '0', '1280x800x24', '-nolisten', 'tcp'], env=env, stdout=xf, stderr=xf)
    p = None
    try:
        time.sleep(1)
        p = subprocess.Popen(commands, cwd=app, env=env, stdout=af, stderr=af)
        start = time.monotonic()
        while time.monotonic() - start < 20 and p.poll() is None:
            try:
                with urllib.request.urlopen('http://127.0.0.1:8800/pjeOffice/api', timeout=1) as r:
                    body = r.read()
                    result['http'] = {'status': r.status, 'bytes': len(body), 'content_type': r.headers.get('Content-Type')}
                    (out / 'localhost-response').write_bytes(body)
                    break
            except Exception as e:
                result['http_error'] = str(e)
            time.sleep(.25)
        for route in ['/pjeOffice/', '/pjeOffice/versao/']:
            request = urllib.request.Request(
                'http://127.0.0.1:8800' + route + '?u=18', data=b'', method='PUT',
                headers={'Content-Type': 'application/json', 'Force-Preflight': 'true',
                         'Origin': 'http://127.0.0.1:8800'})
            try:
                with urllib.request.urlopen(request, timeout=3) as response:
                    result['http'][route] = {'status': response.status,
                                            'body': response.read().decode('utf-8', 'replace')}
            except urllib.error.HTTPError as error:
                result['http'][route] = {'status': error.code,
                                        'body': error.read().decode('utf-8', 'replace')}
            except OSError as error:
                result['http'][route] = {'error': str(error)}
        result['alive_at_observation'] = p.poll() is None
        result['exit_at_observation'] = p.poll()
        result['observation_seconds'] = round(time.monotonic() - start, 2)
        with (out / 'windows.txt').open('w') as f:
            subprocess.run(['xdotool', 'search', '--name', '.*', 'getwindowname', '%@'], env=env, stdout=f, stderr=subprocess.STDOUT)
    finally:
        for child in [p, x]:
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
(out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
