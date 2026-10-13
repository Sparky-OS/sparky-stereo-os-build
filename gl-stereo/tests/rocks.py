# SPDX-License-Identifier: GPL-2.0-or-later
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path('savers').resolve()))
from frames import receive, acknowledge

out = Path('out/rocks'); out.mkdir(exist_ok=True)
def capture(options, reference=0, oracle=True):
    reader, writer = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    env = os.environ.copy()
    env.pop('LD_PRELOAD',None); env.pop('GL_STEREO',None)
    env['GL_STEREO_FRAME_FD'] = str(writer.fileno())
    if oracle: env['GL_STEREO_ROCKS_ORACLE'] = '1'
    if reference: env['GL_STEREO_ROCKS_REFERENCE'] = str(reference)
    process = subprocess.Popen(['./tests/announce','./out/bin/rocks','-window','-geometry','640x360','-mono',*options],
                               env=env, pass_fds=(writer.fileno(),), start_new_session=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    writer.close(); reader.settimeout(8)
    try:
        last = 0
        for i in range(3 if oracle else 50):
            frame = receive(reader,last)
            raw = os.pread(frame.fd,frame.width*frame.height*4,0)
            picture = np.frombuffer(raw,np.uint8).reshape(frame.height,frame.width,4)[::-1,:,:3].copy()
            last = frame.sequence; acknowledge(reader,frame); frame.close()
        tree = subprocess.check_output(['xwininfo','-root','-tree'], text=True)
        (out/('sbs-tree.txt' if '-sbs' in options else 'legacy-tree.txt')).write_text(tree)
        # Only this saver owns mapped windows on the test display at this point.
        import re
        windows = re.findall(r'(0x[0-9a-f]+) "[^"]*": \("rocks" "Rocks"\)', tree)
        assert windows, tree
        props = subprocess.check_output(['xprop','-id',windows[0], '_KDE_NET_WM_STEREO_CONTENT', '_KDE_NET_WM_STEREO_CONTENT_CLASS'],text=True)
        if '-sbs' in options and not reference:
            assert '_KDE_NET_WM_STEREO_CONTENT(CARDINAL) = 3' in props, props
        else:
            assert '_KDE_NET_WM_STEREO_CONTENT(CARDINAL)' not in props, props
        assert '_KDE_NET_WM_STEREO_CONTENT_CLASS(CARDINAL)' not in props, props
    finally:
        reader.close()
        os.killpg(process.pid,signal.SIGTERM)
        _, error = process.communicate(timeout=3)
    assert not error, error
    return picture

sbs = capture(['-sbs'])
assert sbs.shape == (360,1280,3)
Image.fromarray(sbs).save(out/'sbs.png')
for eye in (0,1):
    reference = capture(['-sbs'],eye+1)
    assert np.array_equal(reference,sbs[:,eye*640:(eye+1)*640])
def disparities(picture):
    measured=[]
    for y in (90,180,270):
        centers=[]
        for eye in (0,1):
            mask=picture[y-25:y+25,eye*640:(eye+1)*640].max(axis=2)>32
            yy,xx=np.where(mask); assert len(xx)>3
            centers.append(xx.mean())
        measured.append(centers[1]-centers[0])
    return np.array(measured)
measured=disparities(sbs)
expected=[2*int(.12*40*(1-30/(z+20))) for z in (10,20,60)]
assert np.max(np.abs(np.array(measured)-expected)) <= 1, (measured,expected)
assert expected == [0,2,6]
for mutation in (np.concatenate((sbs[:,640:],sbs[:,:640]),axis=1),np.tile(sbs[:,:640],(1,2,1))):
    assert np.max(np.abs(disparities(mutation)-expected))>1
legacy = capture(['-3d','-delta3d','0.12'])
Image.fromarray(legacy).save(out/'red-blue.png')
assert legacy.shape == (360,640,3)
assert (legacy[:,:,0]>32).any() and (legacy[:,:,2]>32).any() and not (legacy[:,:,1]>32).any()
animated=capture(['-sbs','-count','100'],oracle=False)
Image.fromarray(animated).save(out/'animated.png')
assert animated[:,:640].std()>5 and animated[:,640:].std()>5
print('PASS: rocks native SBS eyes match single-eye references; measured',measured,'expected',expected)
print('PASS: rocks preserves red/blue option, layout-only declaration and animated field')
import json
(out/'proof.json').write_text(json.dumps(dict(passed=True,oracle='rocks-native-v1',
    residual_px=float(np.max(np.abs(np.array(measured)-expected))),disparity_bounds_px=[0,6],eye_width=640)))
