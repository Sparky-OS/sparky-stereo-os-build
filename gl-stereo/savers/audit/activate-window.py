#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Focus the sole replay client in an isolated compositor test session."""
import ctypes as c
import re
import subprocess
x=c.CDLL('libX11.so.6')
x.XOpenDisplay.argtypes=[c.c_char_p];x.XOpenDisplay.restype=c.c_void_p
x.XDefaultRootWindow.argtypes=[c.c_void_p];x.XDefaultRootWindow.restype=c.c_ulong
x.XInternAtom.argtypes=[c.c_void_p,c.c_char_p,c.c_int];x.XInternAtom.restype=c.c_ulong
x.XSendEvent.argtypes=[c.c_void_p,c.c_ulong,c.c_int,c.c_long,c.c_void_p]
x.XFlush.argtypes=[c.c_void_p];x.XCloseDisplay.argtypes=[c.c_void_p]
class Message(c.Structure):
    _fields_=[('type',c.c_int),('serial',c.c_ulong),('send_event',c.c_int),('display',c.c_void_p),('window',c.c_ulong),('message_type',c.c_ulong),('format',c.c_int),('data',c.c_long*5)]
class Event(c.Union):
    _fields_=[('message',Message),('padding',c.c_long*24)]
clients=subprocess.check_output(['xprop','-root','_NET_CLIENT_LIST'],text=True)
ids=re.findall(r'0x[0-9a-fA-F]+',clients)
assert len(ids)==1,clients
window=int(ids[0],16);display=x.XOpenDisplay(None);assert display
message=Event();message.message.type=33;message.message.display=display
message.message.window=window;message.message.message_type=x.XInternAtom(display,b'_NET_ACTIVE_WINDOW',0)
message.message.format=32;message.message.data[0]=2
assert x.XSendEvent(display,x.XDefaultRootWindow(display),0,(1<<20)|(1<<19),c.byref(message))
x.XFlush(display);x.XCloseDisplay(display)
