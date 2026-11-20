#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Refuse to silently remove the installed HandBrake's FDK encoder choices."""
import ctypes
import ctypes.util
import json

codec = ctypes.CDLL(ctypes.util.find_library('avcodec'))
codec.avcodec_find_encoder_by_name.argtypes = [ctypes.c_char_p]
codec.avcodec_find_encoder_by_name.restype = ctypes.c_void_p
required = ('aac', 'libfdk_aac', 'ac3', 'eac3', 'alac', 'flac', 'libmp3lame', 'libopus')
available = {name: bool(codec.avcodec_find_encoder_by_name(name.encode())) for name in required}
loaded = sorted({line.split()[-1] for line in open('/proc/self/maps') if '/libavcodec.so.' in line})
print(json.dumps({'libraries': loaded, 'required_encoders': available}, indent=2), flush=True)
missing = [name for name, present in available.items() if not present]
if missing:
    raise SystemExit('Shared FFmpeg lacks required HandBrake encoders: ' + ', '.join(missing))
