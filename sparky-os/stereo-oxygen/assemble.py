#!/usr/bin/env python3
"""Builds stereo-oxygen/ (the theme, rule B at 4 %) and viewer/assets/ (every variant, plain Oxygen pictures,
probes) from out-all/ (the generator's output) and the oxygen-icons checkout."""
import os, shutil, json
Q = '/K3D/temp/partners/queue/stereo-oxygen'; S = Q + '/step1'; OXY = Q + '/oxygen-icons'
ICONS = [l.strip() for l in open(S + '/icons.txt') if l.strip()]
SIZES = [32, 48, 128, 256]
CONTEXT = {'places': 'Places', 'devices': 'Devices', 'apps': 'Applications', 'categories': 'Categories'}
ctxs = sorted({i.split('/')[0] for i in ICONS}, key=list(CONTEXT).index)

# ---- the viewer's assets
A = S + '/viewer/assets'
shutil.rmtree(A, ignore_errors=True)
open(os.makedirs(A) or A + '/list.txt', 'w').write('\n'.join(i.split('/')[1] for i in ICONS) + '\n')
for i in ICONS:
    ctx, name = i.split('/')
    for n in SIZES:
        d = f'{A}/plain/{n}'; os.makedirs(d, exist_ok=True)
        shutil.copy(f'{OXY}/{n}x{n}/{ctx}/{name}.png', f'{d}/{name}.png')
        for rule in 'ABC':
            for pct in '246':
                d = f'{A}/{rule}{pct}/{n}'; os.makedirs(d, exist_ok=True)
                src = f'{S}/out-all/{rule}-{pct}/{n}/{ctx}/{name}'
                shutil.copy(src + '.png', f'{d}/{name}.png')
                for t in ('front', 'back'):
                    shutil.copy(f'{src}.probe-{t}.png', f'{d}/{name}.probe-{t}.png')

# ---- the theme (rule B, 4 %)
T = S + '/stereo-oxygen'
shutil.rmtree(T, ignore_errors=True)
stereo_dirs = [f'stereo/{n}x{n}/{c}' for n in SIZES for c in ctxs]
os.makedirs(T + '/plain/16x16/actions')
open(T + '/plain/16x16/actions/README', 'w').write(
    'Placeholder folder: it holds no icons. It keeps the theme valid in loaders that require an existing folder\n'
    'in Directories (KDE KIconLoader, GTK); the stereo pictures are in stereo/, listed under X-StereoDirectories.\n')
idx = ['# Stereo Oxygen: a derived work of the Oxygen icon theme (KDE, frameworks/oxygen-icons v6.28.0), whose\n'
       '# icons are licensed LGPL-3.0-or-later; these generated icons keep that licence (see COPYING, LGPL-3.0-or-later.txt).\n'
       '[Icon Theme]\nName=Stereo Oxygen\nComment=Oxygen, in stereo\nInherits=oxygen\n'
       'Directories=plain/16x16/actions\n'
       'X-StereoDirectories=' + ','.join(stereo_dirs) + '\n\n'
       '[plain/16x16/actions]\nSize=16\nContext=Actions\nType=Fixed\n']
for n in SIZES:
    for c in ctxs:
        idx.append(f'\n[stereo/{n}x{n}/{c}]\nX-StereoSize={n}\nContext={CONTEXT[c]}\nType=Fixed\nX-StereoLayout=sbs-left-first\n')
open(T + '/index.theme', 'w').write(''.join(idx))
for i in ICONS:
    ctx, name = i.split('/')
    for n in SIZES:
        d = f'{T}/stereo/{n}x{n}/{ctx}'; os.makedirs(d, exist_ok=True)
        shutil.copy(f'{S}/out-all/B-4/{n}/{ctx}/{name}.png', f'{d}/{name}.png')
shutil.copy(OXY + '/COPYING', T + '/COPYING')
shutil.copy(OXY + '/LICENSES/LGPL-3.0-or-later.txt', T + '/LGPL-3.0-or-later.txt')
print('theme folders:', len(stereo_dirs), 'icons:', len(ICONS) * len(SIZES))
