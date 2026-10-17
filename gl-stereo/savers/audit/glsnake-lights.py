#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""glsnake's second light (owning-settings.json): render the captured frame, and a later one after
new shapes have begun, with the default settings, with each light alone and with none, on the
fixture's clock.

At each frame the three single-light pictures must differ, the default must equal exactly one of
them (the light on at that frame), and none switched on must equal the default.
usage: glsnake-lights.py <output.json> <fixture.so>"""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from controller import read_display

output, fixture = Path(sys.argv[1]), str(Path(sys.argv[2]).resolve())
frames = os.environ.get('AUDIT_LIGHT_FRAMES', '120 600').split()
settings = {'default': [], 'viewer': ['-no-lamp-light', '-no-sun-light'], 'lamp': ['-no-viewer-light', '-no-sun-light'],
            'sun': ['-no-viewer-light', '-no-lamp-light'], 'none': ['-no-viewer-light', '-no-lamp-light', '-no-sun-light']}
def render(arguments, frame, case):
    """The saver's picture at this frame, stock, on the fixture's clock (as mono.py takes it)."""
    read, write = os.pipe()
    server = subprocess.Popen(['Xvfb', '-displayfd', str(write), '-screen', '0', '1280x720x24', '-ac', '-noreset', '-nolisten', 'tcp'],
                              pass_fds=(write,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(write); process = None
    try:
        env = {k: v for k, v in os.environ.items() if not k.startswith(('GL_STEREO', 'AUDIT_')) and k not in ('LD_PRELOAD', 'DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY')}
        env.update(DISPLAY=read_display(read), LIBGL_ALWAYS_SOFTWARE='1', LP_NUM_THREADS='4', LD_PRELOAD=fixture,
                   AUDIT_FRAME=frame, AUDIT_CAPTURE=str(case/'frame.ppm'), AUDIT_READY=str(case/'ready'))
        process = subprocess.Popen(['setarch', 'x86_64', '-R', '/usr/libexec/xscreensaver/glsnake', '-window', '-geometry', '640x360', *arguments],
                                   env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        deadline = time.monotonic() + 60
        while not (case/'ready').exists() and process.poll() is None and time.monotonic() < deadline: time.sleep(.05)
        assert (case/'ready').exists(), (case.name, 'no frame')
        return np.array(Image.open(case/'frame.ppm').convert('RGB'))
    finally:
        os.close(read)
        if process:
            try: os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            process.wait()
        server.terminate(); server.wait(timeout=3)

pictures = {}
with tempfile.TemporaryDirectory(prefix='glsnake-lights-', dir=output.parent) as scratch:
    for frame in frames:
        for name, arguments in settings.items():
            case = Path(scratch)/f'{name}-{frame}'; case.mkdir()
            pictures[name, frame] = render(arguments, frame, case)
result = dict(executable_sha256=hashlib.sha256(Path('/usr/libexec/xscreensaver/glsnake').read_bytes()).hexdigest(), frames={})
singles = ('viewer', 'lamp', 'sun')
passed = True
for frame in frames:
    digest = {name: hashlib.sha256(pictures[name, frame].tobytes()).hexdigest() for name in settings}
    distinct = len({digest[n] for n in singles}) == 3 and all(pictures[n, frame].std() > 1 for n in singles)
    matches = [n for n in singles if digest[n] == digest['default']]
    record = dict(pixels_sha256=digest, single_lights_distinct=distinct, light_on=matches[0] if len(matches) == 1 else None,
                  none_equals_default=digest['none'] == digest['default'])
    record['passed'] = distinct and len(matches) == 1 and record['none_equals_default']
    result['frames'][frame] = record; passed = passed and record['passed']
result['passed'] = passed
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'passed': passed, 'light_on': {f: r['light_on'] for f, r in result['frames'].items()}}))
sys.exit(0 if passed else 1)
