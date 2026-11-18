#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
"""Select the backend explicitly and carry Graphics' stable identity to every native job."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
sys.path.insert(0, '/usr/lib/sparky-stereo-apt')
import sparky_install_downloads as language


def say(key, **fields):
    data = json.loads(Path('/usr/share/sparky-install-models/messages.json').read_text())
    text = data.get(language.language(), data['en'])[key].format(**fields)
    print(text, file=sys.stderr, flush=True)
    if not sys.stderr.isatty() and (os.environ.get('WAYLAND_DISPLAY') or os.environ.get('DISPLAY')):
        subprocess.run(['/usr/bin/yad', '--error', '--title=Spirula Studio', '--text='+text], check=False)


def main():
    args = sys.argv[1:]
    backend = 'vulkan'
    if args and args[0].startswith('--compute-backend='):
        backend = args.pop(0).split('=', 1)[1]
    elif args[:1] == ['--compute-backend']:
        if len(args) < 2:
            return 2
        backend = args[1]
        args = args[2:]
    if backend not in ('vulkan', 'cuda'):
        return 2
    binary = Path('/usr/lib/spirula-studio') / backend / 'spirula'
    if not binary.is_file():
        say('backend', backend=backend, package='spirula-studio-cuda' if backend=='cuda' else 'spirula-studio')
        return 1
    if args[:1] in (['--help'], ['--version']):
        os.execv(str(binary), [str(binary), *args])
    try:
        command = ['/usr/bin/sparky-stereo-gpu-env']
        gpu = subprocess.check_output([*command, '--app', 'spirula-studio.desktop', '--3d', '--print', 'id'], text=True).strip()
        if not re.fullmatch(r'pci-[0-9a-f]{4,8}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]', gpu):
            raise ValueError(gpu)
        # Resolve the environment for this same identity, not a second Automatic choice.
        lines = subprocess.check_output([*command, '--choice', gpu, '--3d', '--print', 'env'], text=True).splitlines()
    except (OSError, ValueError, subprocess.CalledProcessError):
        say('graphics')
        return 1
    env = dict(os.environ)
    for key in ('DRI_PRIME','__NV_PRIME_RENDER_OFFLOAD','__GLX_VENDOR_LIBRARY_NAME','__VK_LAYER_NV_optimus','VK_LOADER_DRIVERS_SELECT','VK_LOADER_DRIVERS_DISABLE'):
        env.pop(key, None)
    for line in lines:
        key, value = line.split('=', 1)
        if not re.fullmatch('[A-Z_][A-Z0-9_]*', key):
            raise ValueError(key)
        env[key] = value
    env.pop('CUDA_VISIBLE_DEVICES', None)
    env['SS_EDITION_GPU_PCI'] = gpu
    print(backend.upper()+' | '+gpu, file=sys.stderr, flush=True)
    os.execve(str(binary), [str(binary), *args], env)
    return 1


if __name__ == '__main__':
    sys.exit(main())
