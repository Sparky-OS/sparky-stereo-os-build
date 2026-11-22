#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
import json,sys,time,pyatspi
want=sys.argv[1]
def find(a,depth=0):
 if depth>18:return None
 try:
  if a.name==want and a.getRoleName() in ('check box','button','push button'):return a
  for child in a:
   found=find(child,depth+1)
   if found is not None:return found
 except Exception:pass
 return None
start=time.monotonic()
while time.monotonic()-start<120:
 a=find(pyatspi.Registry.getDesktop(0))
 if a is not None and a.getState().contains(pyatspi.STATE_ENABLED):
  action=a.queryAction();names=[action.getName(i) for i in range(action.nActions)]
  if action.nActions:
   ok=action.doAction(0);print(json.dumps(dict(name=want,actions=names,invoked=ok)));sys.exit(0 if ok else 3)
 time.sleep(.25)
raise SystemExit('No actionable page control: '+want)
