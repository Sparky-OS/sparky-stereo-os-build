# SPDX-License-Identifier: GPL-2.0-or-later
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path('savers').resolve()))
from frames import receive, acknowledge

out = Path('out/starfield'); out.mkdir(parents=True, exist_ok=True)
base = os.environ.copy()
base.pop('LD_PRELOAD', None)
base.pop('GL_STEREO', None)

def launch(extra, broker=True):
    source, writer = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    env = dict(base, LD_PRELOAD=str(Path('libgl-stereo.so').resolve()), GL_STEREO='1', GL_STEREO_FRAME_FD=str(writer.fileno()))
    process = subprocess.Popen(['./tests/announce', './savers/starfield', *extra], env=env,
                               pass_fds=(writer.fileno(),), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, start_new_session=True)
    writer.close()
    if broker:
        reader, sink = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        relay = subprocess.Popen([sys.executable, 'savers/frames.py', str(source.fileno()), str(sink.fileno())],
                                 pass_fds=(source.fileno(), sink.fileno()), stderr=subprocess.PIPE, text=True)
        source.close(); sink.close()
    else:
        reader, relay = source, None
    reader.settimeout(5)
    return process, relay, reader

def stop(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
    return process.communicate(timeout=5)

def pixels(frame):
    raw = os.pread(frame.fd, frame.width * frame.height * 4, 0)
    return np.frombuffer(raw, np.uint8).reshape(frame.height, frame.width, 4)[::-1,:,:3].copy()

process, broker, reader = launch(['--oracle', '--frames', '30'])
last = 0
for _ in range(3):
    frame = receive(reader, last)
    picture = pixels(frame)
    assert picture.shape == (360,1280,3)
    acknowledge(reader, frame); last = frame.sequence; frame.close()
reader.close()
stop(process)
broker.communicate(timeout=5)
Image.fromarray(picture).save(out/'oracle.png')

def disparities(picture):
    values = []
    for channel in range(3):
        centers = []
        for eye in (0,1):
            a = picture[:,eye*640:(eye+1)*640]
            mask = (a[:,:,channel] > 60) & (a[:,:,(channel+1)%3] == 0) & (a[:,:,(channel+2)%3] == 0)
            y, x = np.where(mask)
            assert len(x) == 49, (channel, eye, len(x))
            centers.append(x.mean())
        values.append(centers[1]-centers[0])
    return np.array(values)

expected = 640*.01*(1-5/np.array([6,10,20]))
actual = disparities(picture)
assert np.max(np.abs(actual-expected)) <= 1, (actual, expected)
assert not picture[260:].any(), 'screen-plane star must be invisible'
red = picture[:,:,0][(picture[:,:,0] > 0) & (picture[:,:,1] == 0)]
assert np.all(np.abs(red.astype(int)-128) <= 1), 'near stars must fade'
for mutation in (np.concatenate((picture[:,640:],picture[:,:640]),axis=1), np.tile(picture[:,:640],(1,2,1))):
    assert np.max(np.abs(disparities(mutation)-expected)) > 1
for eye, label in enumerate(('left','right')):
    path = out/f'reference-{label}.ppm'
    subprocess.run(['./savers/starfield', '--oracle', '--frames','1', '--fast', f'--reference-{label}', '--capture',str(path)], env=base, check=True)
    assert np.array_equal(np.array(Image.open(path)), picture[:,eye*640:(eye+1)*640])
print('PASS: starfield native cameras match independent mono eye renders; measured',actual.tolist(),'expected',expected.tolist())
print('PASS: fade at depth 6, invisible at convergence, swapped and copied-eye mutations rejected')
levels=[]
for depth, intensity in ((5,0),(5.25,11),(5.5,40),(6,128),(6.5,215),(6.75,244),(7,255)):
    path=out/'fade-probe.ppm'
    subprocess.run(['./savers/starfield','--oracle','--probe-depth',str(depth),'--frames','1','--fast',
                    '--reference-left','--capture',str(path)],env=base,check=True,stdout=subprocess.DEVNULL)
    level=int(np.array(Image.open(path))[:,:,0].max()); levels.append(level)
    assert abs(level-intensity)<=1, (depth,level,intensity)
assert levels==sorted(levels)
print('PASS: seven measured fade levels follow the continuous camera-depth fade',levels)

process, broker, reader = launch(['--frames','90'])
frame = receive(reader); scene = pixels(frame); acknowledge(reader,frame); frame.close()
assert scene[:,:640].std() > 5 and scene[:,640:].std() > 5
assert not scene[140:220,240:400].any() and not scene[140:220,880:1040].any()
Image.fromarray(scene).save(out/'flight.png')
for eye,label in enumerate(('left','right')):
    path=out/f'flight-reference-{label}.ppm'
    subprocess.run(['./savers/starfield','--frames','1','--fast',f'--reference-{label}','--capture',str(path)],
                   env=base,check=True,stdout=subprocess.DEVNULL)
    reference = np.array(Image.open(path))
    eye_scene = scene[:,eye*640:(eye+1)*640]
    # Point clipping at the physical window edge differs from an eye viewport.
    assert np.array_equal(reference[1:-1,1:-1], eye_scene[1:-1,1:-1])
# A dead consumer must stop the broker promptly, without keeping the producer blocked.
reader.close(); broker.communicate(timeout=3)
assert broker.returncode != 0
output, error = process.communicate(timeout=5)
assert process.returncode == 0 and 'world_updates=90' in output and not error, (output,error)

process, _, reader = launch(['--frames','1000','--fast'], broker=False)
time.sleep(.15)
frame = receive(reader); frame.close()
reader.settimeout(.1)
try:
    receive(reader)
except (socket.timeout, EOFError):
    pass
else:
    raise AssertionError('producer queued more than one unacknowledged frame')
reader.close()
output,error = process.communicate(timeout=60)
assert process.returncode == 0 and 'world_updates=1000' in output and not error
print('PASS: animated field, prompt exclusion, one world update per frame, dead consumer and bounded slow-consumer queue')
import json
(out/'proof.json').write_text(json.dumps(dict(passed=True,oracle='starfield-camera-v1',
    residual_px=float(np.max(np.abs(actual-expected))),disparity_bounds_px=[0,6.4],eye_width=640)))
