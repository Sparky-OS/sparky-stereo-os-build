# SPDX-License-Identifier: GPL-2.0-or-later
import os
from pathlib import Path
import sys
import threading
import time
sys.path.insert(0, str(Path(__file__).resolve().parent.parent/'savers'))
from controller import read_display

def case(parts, expected):
    read, write = os.pipe()
    def producer():
        try:
            for part in parts:
                os.write(write, part)
                time.sleep(.02)
        finally: os.close(write)
    thread = threading.Thread(target=producer)
    thread.start()
    try:
        try: actual = read_display(read, .5)
        except RuntimeError: actual = None
        assert actual == expected, (parts, actual, expected)
    finally:
        thread.join()
        os.close(read)

case([b'12', b'3', b'\n'], ':123')
case([b'0\n'], ':0')
case([b'123'], None)
case([b'bad\n'], None)
case([], None)
read, write = os.pipe()
try:
    try: read_display(read, .02)
    except RuntimeError: pass
    else: raise AssertionError('timeout accepted')
finally: os.close(read); os.close(write)
print('PASS: fragmented display line, malformed/unterminated input, EOF and bounded timeout')
