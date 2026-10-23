#!/usr/bin/env python3
import os, pathlib, subprocess
out = pathlib.Path('/w/captures') / os.environ['SCENARIO']
out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
for key in ('LD_PRELOAD', 'RIG_COMPOSITOR_RENDER_NODE', '__EGL_VENDOR_LIBRARY_FILENAMES', 'QT_QPA_PLATFORM', 'DRI_PRIME'):
    env.pop(key, None)
env['WAYLAND_DISPLAY'] = 'order223-route'
env['WAYLAND_DEBUG'] = 'client'
env['LD_LIBRARY_PATH'] = '/w/placebo-build/src:/w/route-prefix/lib:/prev/ffmpeg-build/libavcodec'
installed = os.environ.get('ROUTE_INSTALLED') == '1'
if installed:
    env.pop('LD_LIBRARY_PATH', None)
for api in ('vulkan', 'opengl'):
    for film in ('h264-right8', 'hevc-eyes12', 'h264-2d8'):
        for mode in ('no', 'auto'):
            name = f'{api}-{film}-{mode}'
            env['CAPTURE_OUTPUT'] = str(out/name)
            args = ['/usr/bin/mpv' if installed else '/prev/mpv-build/mpv', '--no-config', '--ao=null', '--vo=gpu-next', '--gpu-api='+api,
                '--gpu-context=wayland'+('vk' if api=='vulkan' else ''), '--hwdec='+mode, '--pause',
                '--screenshot-high-bit-depth=yes', '--geometry=960x540', '--no-terminal',
                '--script=/kit/capture.lua', '--log-file='+str(out/(name+'.mpv.log')), '/prev/fixtures/'+film+'.mkv']
            with (out/(name+'.wayland.log')).open('w') as log:
                subprocess.run(args, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=30, check=True)
            if not (out/(name+'.png')).exists(): raise RuntimeError(name+' has no capture')
