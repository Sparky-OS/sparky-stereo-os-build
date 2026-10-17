#!/usr/bin/env python3
"""typede.py SOCK TEXT : types TEXT into a guest whose keyboard layout is German (pc105 de), by QEMU qcodes."""
import sys, time
sys.path.insert(0, "/K3D/temp/partners/queue/beta-iso-lutz/boot-matrix")
from vmctl import Qmp
DE = {'y': ['z'], 'z': ['y'], 'Y': ['shift', 'z'], 'Z': ['shift', 'y'], '-': ['slash'], '_': ['shift', 'slash'],
      '/': ['shift', '7'], '.': ['dot'], ',': ['comma'], ':': ['shift', 'dot'], ';': ['shift', 'comma'],
      '=': ['shift', '0'], '"': ['shift', '2'], "'": ['shift', 'backslash'], '#': ['backslash'], '|': ['alt_r', 'less'],
      '<': ['less'], '>': ['shift', 'less'], '*': ['shift', 'bracket_right'], '+': ['bracket_right'],
      '~': ['alt_r', 'bracket_right'], '$': ['shift', '4'], '&': ['shift', '6'], '(': ['shift', '8'], ')': ['shift', '9'],
      '!': ['shift', '1'], '%': ['shift', '5'], '?': ['shift', 'minus'], '\\': ['alt_r', 'minus'], '{': ['alt_r', '7'],
      '}': ['alt_r', '0'], '[': ['alt_r', '8'], ']': ['alt_r', '9'], '@': ['alt_r', 'q'], ' ': ['spc'], '\n': ['ret']}
q = Qmp(sys.argv[1])
for ch in " ".join(sys.argv[2:]):
    if ch in DE:
        k = DE[ch]
    elif ch.isupper():
        k = ['shift', ch.lower()]
    else:
        k = [ch]
    q.cmd("send-key", keys=[{"type": "qcode", "data": x} for x in k])
    time.sleep(0.04)
