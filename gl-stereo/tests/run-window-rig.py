# SPDX-License-Identifier: GPL-2.0-or-later
"""Use the read-only kwin-package-17 harness on this lane's render-only rig."""
import json
from pathlib import Path
import os
import subprocess
import sys
import shutil
repo = Path.cwd()
name = sys.argv[1]
library = repo / ('out/window-sizing/before.so' if name == 'before' else 'libgl-stereo.so')
config = {'cmd': [str(repo / 'out/window-sizing/client')],
          'cwd': str(repo), 'env': {'LD_PRELOAD': str(library), 'GL_STEREO': '1'},
          'caps': [6, 7], 'x11_name': 'gl-stereo-sizing'}
if name == 'quad':
    config['env']['TEST_QUAD'] = '1'
if name == 'future':
    config['env'].update(TEST_SUPPORT_VERSION='4', TEST_RIG='1')
if name == 'gears':
    config.update(cmd=['glxgears', '-geometry', '400x300+100+100'], x11_name='glxgears')
bin_dir = repo / 'out/window-sizing/bin'
bin_dir.mkdir(exist_ok=True)
shutil.copyfile('/usr/bin/kwin_wayland', bin_dir / 'kwin_wayland')
(bin_dir / 'kwin_wayland').chmod(0o755)
env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE='1', PATH=str(bin_dir)+':'+os.environ['PATH'])
subprocess.run(['dbus-run-session', '--', 'python3', '/rig/drv.py',
                str(repo / 'out/window-sizing' / name), json.dumps(config)], env=env, check=True)
