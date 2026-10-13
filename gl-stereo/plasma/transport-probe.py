# SPDX-License-Identifier: GPL-2.0-or-later
import os, sys, socket, subprocess, struct
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'savers'))
from frames import receive
from PIL import Image
control, child_control = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
consumer, child_consumer = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
p = subprocess.Popen([sys.executable, 'savers/controller.py', sys.argv[1], str(child_control.fileno()), str(child_consumer.fileno())], pass_fds=(child_control.fileno(),child_consumer.fileno()))
child_control.close(); child_consumer.close()
try:
    control.send(b'{"locked":true,"display_on":true,"on_ac":true}')
    consumer.settimeout(10)
    for i in range(5):
        frame = receive(consumer, i)
        if i == 4:
            Image.frombytes("RGBA", (frame.width, frame.height), os.pread(frame.fd,frame.width*frame.height*4,0)).transpose(Image.Transpose.FLIP_TOP_BOTTOM).save(sys.argv[2])
        consumer.send(struct.pack('<I',frame.sequence))
        frame.close()
finally:
    control.send(b'{"event":"shutdown"}')
    p.wait(timeout=5)
