#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
import json,sys,time,pyatspi

def find(a,want,depth=0):
 if depth>18:return None
 try:
  if a.name==want and a.getRoleName() in ('check box','button','push button'):return a
  for child in a:
   found=find(child,want,depth+1)
   if found is not None:return found
 except Exception:pass
 return None

def main(want):
 start=time.monotonic()
 while time.monotonic()-start<120:
  action=None
  try:
   a=find(pyatspi.Registry.getDesktop(0),want)
   if a is not None and a.getState().contains(pyatspi.STATE_ENABLED):
    candidate=a.queryAction();names=[candidate.getName(i) for i in range(candidate.nActions)]
    if candidate.nActions:action=candidate
  except Exception as error:
   print(json.dumps(dict(name=want,discovery_error=str(error),elapsed=time.monotonic()-start)),flush=True)
  if action is not None:
   # Never repeat activation: a lost reply could follow a successful toggle.
   ok=action.doAction(0);print(json.dumps(dict(name=want,actions=names,invoked=ok)),flush=True)
   return 0 if ok else 3
  time.sleep(.25)
 raise SystemExit('No actionable page control: '+want)

if __name__=='__main__':sys.exit(main(sys.argv[1]))
