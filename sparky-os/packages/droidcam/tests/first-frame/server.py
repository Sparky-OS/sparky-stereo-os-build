#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/24
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: a stand-in for the DroidCam app's video side, for the client's tests without a phone. It answers the request with the
# 9 byte header the app 6.28 sent (640x480 and five bytes the client ignores, recorded 2026-11-24), waits DELAY seconds the way the app
# does while it starts the phone's camera, then sends frames as the app does: 4 bytes little endian length, then a JPEG.
# Usage: server.py PORT DELAY FRAMES hold|close|reset|bursts|cut:GAP|cutstall [FRAME.jpg]
#   cut:GAP: FRAMES whole frames, then one frame cut in two halves with GAP seconds of silence between them, then 20 whole frames, then it holds
#   cutstall: FRAMES whole frames, then the length and half of a frame, then silence for ever   (bursts: FRAMES frames, 8 s of silence, again; the phone left gaps of 5 s and more on 2026-11-24, and the staged client's timeout is about 6 s)
import socket, struct, sys, time, os
port, delay, frames, after = int(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
jpg = open(sys.argv[5] if len(sys.argv) > 5 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'frame-640x480.jpg'), 'rb').read()
server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', port))
server.listen(1)
print('listening', port, flush=True)
conn, _ = server.accept()
request = conn.recv(256)
print('request', request.decode('latin-1'), flush=True)
if after == 'reset':
    conn.close()
    sys.exit(0)
conn.sendall(bytes.fromhex('028001e021f5e87f30'))
time.sleep(delay)
def frame():
    return struct.pack('<I', len(jpg)) + jpg
try:
    if after.startswith('cut'):
        for _ in range(frames):
            conn.sendall(frame())
            time.sleep(1 / 30)
        data = frame()
        half = 4 + len(jpg) // 2
        conn.sendall(data[:half])
        if after == 'cutstall':
            time.sleep(300)
        time.sleep(float(after.split(':')[1]))
        conn.sendall(data[half:])
        for _ in range(20):
            conn.sendall(frame())
            time.sleep(1 / 30)
        time.sleep(300)
    while True:
        for _ in range(frames):
            conn.sendall(struct.pack('<I', len(jpg)) + jpg)
            time.sleep(1 / 30)
        if after != 'bursts':
            break
        time.sleep(8)
    if after == 'hold':
        time.sleep(300)
except (BrokenPipeError, ConnectionResetError):
    pass
conn.close()
