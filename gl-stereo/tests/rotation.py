# SPDX-License-Identifier: GPL-2.0-or-later
import copy
import json
import os
from pathlib import Path
import random
import socket
import subprocess
import sys
import time
sys.path.insert(0,str(Path('savers').resolve()))
from catalogue import Rotation, active, eligible, load, digest
from frames import receive, acknowledge
from PIL import Image, ImageDraw
import numpy as np

path='out/eligibility/catalogue.json'
entries=load(path)
assert {'starfield','rocks'} <= {entry['id'] for entry in entries}
for mutation in ('failed','missing','stale','negative','excess','residual'):
    bad=copy.deepcopy(entries[0])
    if mutation=='failed': bad['proof']['passed']=False
    elif mutation=='missing': del bad['proof']
    elif mutation=='stale': bad['executable_sha256']='0'*64
    elif mutation=='negative': bad['proof']['disparity_bounds_px'][0]=-1000
    elif mutation=='excess': bad['proof']['disparity_bounds_px'][1]=1000
    elif mutation=='residual': bad['proof']['residual_px']=2
    assert not eligible(bad)
screen_level=copy.deepcopy(entries[0])
screen_level['proof'].update(placement='screen-level',disparity_bounds_px=[-.01*screen_level['proof']['eye_width'],.005*screen_level['proof']['eye_width']])
assert eligible(screen_level)
screen_level['proof']['disparity_bounds_px'][0]=-.021*screen_level['proof']['eye_width']
assert not eligible(screen_level)
rotation=Rotation(entries,random.Random(3))
last=None
for _ in range(5):
    bag=[]
    for i in range(len(entries)):
        item=rotation.next()['id']; assert item!=last or len(entries)==1
        bag.append(item); last=item
    assert set(bag)=={entry['id'] for entry in entries}
for entry in entries: rotation.exclude(entry['id'])
assert rotation.next() is None
for locked in (False,True):
    for display_on in (False,True):
        for on_ac in (False,True):
            assert active(dict(locked=locked,display_on=display_on,on_ac=on_ac)) == (locked and display_on and on_ac)
print('PASS: failed, missing, stale and uncomfortable proofs excluded; random bags cover all eligible entries without immediate repeats')

control, controller_control=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
consumer, controller_consumer=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
log=Path('out/eligibility/controller.log').open('w')
process=subprocess.Popen([sys.executable,'savers/controller.py',path,str(controller_control.fileno()),str(controller_consumer.fileno())],
                          pass_fds=(controller_control.fileno(),controller_consumer.fileno()),stdout=log,stderr=log)
controller_control.close(); controller_consumer.close()
def state(**changes):
    value=dict(locked=True,display_on=True,on_ac=True); value.update(changes)
    control.send(json.dumps(value).encode())
def next_frame():
    consumer.settimeout(8)
    frame=receive(consumer)
    assert frame.width==1280 and frame.height==360
    raw=os.pread(frame.fd,frame.width*frame.height*4,0)
    picture=np.frombuffer(raw,np.uint8).reshape(frame.height,frame.width,4)[::-1,:,:3].copy()
    acknowledge(consumer,frame); frame.close()
    return picture
def no_frames():
    # A frame already in transit may finish; after that no new work is produced.
    consumer.settimeout(.3)
    for _ in range(2):
        try:
            frame=receive(consumer); acknowledge(consumer,frame); frame.close()
        except socket.timeout:
            return
    raise AssertionError('frames continued while inactive')
try:
    state(locked=False); no_frames()
    state(on_ac=False); no_frames()
    state(display_on=False); no_frames()
    state()
    picture=next_frame()
    Image.fromarray(picture).save('out/eligibility/controller-frame.png')
    preview=Image.fromarray(picture)
    draw=ImageDraw.Draw(preview)
    for origin in (0,640):
        draw.rectangle((origin+190,135,origin+450,225),fill=(24,28,35))
        draw.text((origin+215,158),'Unlock prompt (test consumer)',fill='white')
        draw.rectangle((origin+215,185,origin+425,207),outline='white')
    pixels=np.array(preview)
    assert np.array_equal(pixels[135:226,190:451],pixels[135:226,830:1091])
    preview.save('out/eligibility/greeter-consumer.png')
    for _ in range(len(entries)):
        control.send(b'{"event":"rotate"}')
        next_frame()
    state(display_on=False); no_frames()
    state(on_ac=False); no_frames()
    state(locked=False); no_frames()
    control.send(b'{"event":"shutdown"}')
    assert process.wait(timeout=5)==0
finally:
    control.close(); consumer.close(); log.close()
    if process.poll() is None: process.terminate(); process.wait(timeout=5)
print('PASS: private-display controller streams a random rotation and stops on screen-off, battery, unlock and shutdown')

# A crashing producer is excluded for this session, yielding the static fallback.
crash=copy.deepcopy(entries[0]); crash['id']='crash-test'; crash['command']=['/bin/false']
crash['executable_sha256']=digest('/bin/false')
crash_path=Path('out/eligibility/crash-catalogue.json'); crash_path.write_text(json.dumps([crash]))
control, child_control=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
consumer, child_consumer=socket.socketpair(socket.AF_UNIX,socket.SOCK_SEQPACKET)
with Path('out/eligibility/crash.log').open('w') as output:
    process=subprocess.Popen([sys.executable,'savers/controller.py',str(crash_path),str(child_control.fileno()),str(child_consumer.fileno())],
                             pass_fds=(child_control.fileno(),child_consumer.fileno()),stdout=output,stderr=output)
child_control.close(); child_consumer.close()
try:
    control.send(b'{"locked":true,"display_on":true,"on_ac":true}')
    consumer.settimeout(2)
    try: receive(consumer)
    except socket.timeout: pass
    else: raise AssertionError('crashing producer supplied a frame')
    control.send(b'{"event":"rotate"}'); time.sleep(.2)
    control.send(b'{"event":"shutdown"}')
    assert process.wait(timeout=5)==0
finally:
    control.close(); consumer.close()
    if process.poll() is None: process.terminate(); process.wait(timeout=5)
assert Path('out/eligibility/crash.log').read_text().count('started crash-test')==1
print('PASS: producer death removes its entry and leaves static fallback without relaunch loops')
