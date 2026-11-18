#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Capture the actual Yad text and window; only release fixtures change between cases."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

case = Path(os.environ['CASE'])
shim = case / 'shim'
shim.mkdir(exist_ok=True)
wrapper = shim / 'yad'
wrapper.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['CASE']) / (os.environ['TOOL'] + '-yad-' + str(os.getpid()) + '.json')
p.write_text(json.dumps(sys.argv[1:], ensure_ascii=False))
os.execv('/usr/bin/yad', ['yad', *sys.argv[1:]])
''')
wrapper.chmod(0o755)
env = os.environ | dict(PATH=str(shim) + ':' + os.environ['PATH'], GDK_BACKEND='x11')
# Read only the display credentials of this container's private Plasma login.
pid = subprocess.check_output(['pgrep', '-x', 'plasmashell'], text=True).strip().splitlines()[-1]
for item in Path(f'/proc/{pid}/environ').read_bytes().split(b'\0'):
    if item.startswith((b'DISPLAY=', b'XAUTHORITY=')):
        k, v = item.decode().split('=', 1)
        env[k] = v
assert env.get('DISPLAY'), 'Private login has no Xwayland display'
paths = ['/etc/os-release', '/etc/lsb-release', '/etc/sparky/info']
def hashes():
    return {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in paths}
before = hashes()
results = {}
for tool in ['sparky-about', 'sparky-system']:
    with (case / (tool + '.log')).open('w') as log:
        child = subprocess.Popen([tool], env=env | dict(TOOL=tool), stdout=log, stderr=log, start_new_session=True)
        try:
            time.sleep(5)
            assert child.poll() is None, f'{tool} closed before capture'
            subprocess.run(['python3', '/rig-scripts/login-splash/shot.py', 'Virtual-0', str(case / (tool + '.png'))], check=True)
            text = '\n'.join(arg for p in case.glob(tool + '-yad-*.json') for arg in json.loads(p.read_text()) if arg.startswith('--text='))
            (case / (tool + '-text.txt')).write_text(text + '\n')
            results[tool] = os.environ['EXPECT_NAME'] in text
        finally:
            try: os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            child.wait(timeout=5)
    time.sleep(1)
results['releaseFilesUnchanged'] = before == hashes()
(case / 'display-names.json').write_text(json.dumps(dict(expected=os.environ['EXPECT_NAME'], checks=results, before=before, after=hashes()), indent=2) + '\n')
print(json.dumps(results, indent=2))
raise SystemExit(0 if all(results.values()) else 1)
