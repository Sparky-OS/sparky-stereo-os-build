#!/usr/bin/env python3
"""Record accessibility events in the rig's private session, without speech."""
import json,sys,time
import pyatspi
from gi.repository import GLib
out=open(sys.argv[1],'w',buffering=1)
def event(e):
    try:
        item=dict(time=time.monotonic(),type=e.type,detail1=e.detail1,detail2=e.detail2,data=str(e.any_data),source_name=e.source.name)
    except Exception as error:
        item=dict(error=str(error),type=e.type)
    out.write(json.dumps(item)+'\n')
pyatspi.Registry.registerEventListener(event,'object:announcement')
GLib.timeout_add_seconds(100,lambda: (pyatspi.Registry.stop(),False)[1])
pyatspi.Registry.start()
