# SPDX-License-Identifier: GPL-2.0-or-later
"""A still program under a KWin that reads its stereo declaration late.

KWin is held still after it has mapped the window and before the program makes its context
current (where the layer declares the window), for HOLD seconds; the program draws once into
the single-width window and then only when the window system asks. After KWin resumes and
doubles the window, both eyes must show the program's picture with no input.
usage: run-late-doubling.py <scratch> <client> <library> <capture tool>
"""
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

root, client, library, capture = (Path(p) for p in sys.argv[1:5])
if len(sys.argv) == 5:
    root.mkdir(parents=True, exist_ok=True)
    for directory in ('home', 'config', 'runtime'): (root/directory).mkdir(exist_ok=True)
    (root/'runtime').chmod(0o700)
    env = {k: v for k, v in os.environ.items() if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'LD_PRELOAD', 'LIBGL_ALWAYS_SOFTWARE', 'GALLIUM_DRIVER')}
    env.update(HOME=str(root/'home'), XDG_CONFIG_HOME=str(root/'config'), XDG_RUNTIME_DIR=str(root/'runtime'),
               KWIN_COMPOSE='O2', KWIN_WAYLAND_NO_PERMISSION_CHECKS='1', KWIN_SCREENSHOT_NO_PERMISSION_CHECKS='1', LP_NUM_THREADS='4')
    command = ['dbus-run-session', '--', 'kwin_wayland', '--virtual', '--width', '1280', '--height', '800', '--xwayland',
               '--socket', 'gl-stereo-late', '--no-global-shortcuts', '--exit-with-session',
               ' '.join([sys.executable, str(Path(__file__).resolve()), *sys.argv[1:5], '--session'])]
    with (root/'kwin.log').open('w') as log:
        subprocess.run(command, env=env, stdout=log, stderr=log, check=True, timeout=120)
    result = (root/'result.txt').read_text()
    print(result, end='')
    sys.exit(0 if result.startswith('PASS') else 1)

import numpy as np
from PIL import Image
hold = float(os.environ.get('HOLD', '8'))
env = dict(os.environ, LD_PRELOAD=str(library), GL_STEREO='1', GL_STEREO_DEBUG='1', LIBGL_ALWAYS_SOFTWARE='1',
           TEST_MAPPED=str(root/'mapped'), TEST_GO=str(root/'go'))
with (root/'client.log').open('w') as log:
    process = subprocess.Popen([str(client)], env=env, stdout=log, stderr=log, start_new_session=True)
try:
    while not (root/'mapped').exists():
        assert process.poll() is None, 'client exited'
        time.sleep(.005)
    if hold:
        subprocess.run(['pkill', '-STOP', '-x', 'kwin_wayland'], check=True)
    (root/'go').write_text('')
    time.sleep(hold)
    if hold:
        subprocess.run(['pkill', '-CONT', '-x', 'kwin_wayland'], check=True)
    time.sleep(3)
    subprocess.run([str(capture), str(root/'kwin.png'), 'window'], check=True, timeout=30)
    a = np.array(Image.open(root/'kwin.png').convert('RGB'))
    counts = []
    if a.shape == (300, 800, 3):
        for eye in (a[:, :400], a[:, 400:]):
            red = (eye[:, :, 0] > 200) & (eye[:, :, 1] < 50) & (eye[:, :, 2] < 50)
            blue = (eye[:, :, 2] > 200) & (eye[:, :, 1] < 50) & (eye[:, :, 0] < 50)
            counts.append((int(red.sum()), int(blue.sum())))
    draws = [line.strip() for line in (root/'client.log').read_text().splitlines() if line.startswith(('draw', 'configure'))]
    passed = a.shape == (300, 800, 3) and counts == [(18000, 18000), (18000, 18000)]
    (root/'result.txt').write_text(f"{'PASS' if passed else 'FAIL'}: held {hold:g} s, composed {a.shape[1]}x{a.shape[0]}, "
                                   f"red/blue per eye {counts}, program: {'; '.join(draws)}\n")
finally:
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
