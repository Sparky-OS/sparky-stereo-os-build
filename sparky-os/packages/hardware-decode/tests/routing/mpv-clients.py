#!/usr/bin/env python3
"""Measure a player's own counters in an isolated compositor session."""
import json, os, pathlib, resource, socket, subprocess, time
out = pathlib.Path('/w/final') / os.environ['SCENARIO']
out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
for key in ('LD_PRELOAD', 'RIG_COMPOSITOR_RENDER_NODE', '__EGL_VENDOR_LIBRARY_FILENAMES', 'QT_QPA_PLATFORM', 'DRI_PRIME'):
    env.pop(key, None)
env['WAYLAND_DISPLAY'] = 'order223-route'
env['WAYLAND_DEBUG'] = 'client'
env['LD_LIBRARY_PATH'] = ('/w/placebo-build/src:' if not os.environ.get('ROUTE_BEFORE') else '') + '/w/route-prefix/lib:/prev/ffmpeg-build/libavcodec'
for api in ('vulkan', 'opengl'):
    for film in ('perf-3d.mp4', 'perf-2d1080.mkv'):
        name = api + '-' + film.split('.')[0]
        ipc = '/tmp/' + name + '.sock'
        log = (out / (name + '.log')).open('w')
        args = ['/prev/mpv-build/mpv', '--no-config', '--ao=null', '--vo=gpu-next', '--gpu-api='+api,
                '--gpu-context=wayland' + ('vk' if api == 'vulkan' else ''), '--hwdec=auto',
                '--dump-stats='+str(out / (name+'.stats')), '--geometry=1920x1080', '--input-ipc-server='+ipc,
                '--no-terminal', '--log-file='+str(out / (name + '.mpv.log')), '--msg-level=all=v', '/w/fixtures/'+film]
        start = time.monotonic()
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        proc = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
        samples = []
        try:
            for _ in range(200):
                if pathlib.Path(ipc).exists() or proc.poll() is not None: break
                time.sleep(.05)
            sock = socket.socket(socket.AF_UNIX)
            sock.settimeout(20)
            sock.connect(ipc)
            stream = sock.makefile('r')
            seq = 0
            def command(command):
                global seq
                seq += 1
                sock.sendall((json.dumps({'command': command, 'request_id': seq})+'\n').encode())
                while True:
                    reply = json.loads(stream.readline())
                    if reply.get('request_id') == seq:
                        return reply
            for _ in range(16):
                row = {'wall': time.monotonic()-start}
                for prop in ('time-pos', 'hwdec-current', 'hwdec-interop', 'frame-drop-count',
                             'decoder-frame-drop-count', 'vo-delayed-frame-count', 'estimated-vf-fps',
                             'vo-passes', 'video-params', 'video-out-params'):
                    row[prop] = command(['get_property', prop])
                samples.append(row)
                time.sleep(.5)
            command(['quit'])
            proc.wait(10)
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(10)
            log.close()
        end = resource.getrusage(resource.RUSAGE_CHILDREN)
        wall = time.monotonic()-start
        result = {'samples': samples, 'args': args, 'exit': proc.returncode, 'wall': wall,
                  'cpu_seconds': end.ru_utime+end.ru_stime-before.ru_utime-before.ru_stime}
        result['cpu_percent'] = result['cpu_seconds']/wall*100
        (out / (name + '.json')).write_text(json.dumps(result, indent=2)+'\n')
        if proc.returncode != 0: raise RuntimeError(name + ' failed')
