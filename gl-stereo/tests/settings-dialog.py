# SPDX-License-Identifier: GPL-2.0-or-later
import runpy
import os
import tkinter as tk
from PIL import ImageGrab
module = runpy.run_path('./gl-stereo-run', run_name='launcher_test')
original = tk.Tk
seen = []
def root():
    widget = original()
    def verify():
        def walk(parent):
            for child in parent.winfo_children():
                if 'text' in child.keys(): seen.append(child.cget('text'))
                walk(child)
        walk(widget)
        for title in ('Enable 3D', 'Render resolution per eye', 'Display settings', 'Launch'):
            assert title in seen
        ImageGrab.grab(xdisplay=os.environ['DISPLAY']).save('out/launcher/dialog-%d.png' % len(shots))
        shots.append(widget)
        widget.destroy()
    widget.after(500,verify)
    return widget
shots = []
tk.Tk = root
# Where Mesa serves the display the dialog has no OpenGL row; where NVIDIA's OpenGL does,
# the row offers zink and NVIDIA's own OpenGL, per program.
assert module['settings'](True,'auto','zink',False) is None
assert seen and 'OpenGL on NVIDIA' not in seen
seen.clear()
assert module['settings'](True,'auto','nvidia',True) is None
assert 'OpenGL on NVIDIA' in seen
print('PASS: settings dialog controls rendered under private Xvfb, the OpenGL row only on NVIDIA')
