#!/usr/bin/env python3
import pyatspi,json,sys
rows=[]
def walk(a,depth=0):
 if depth>12 or len(rows)>1500:return
 try:
  rows.append(dict(depth=depth,role=a.getRoleName(),name=a.name))
  for c in a:walk(c,depth+1)
 except Exception as e: rows.append(dict(depth=depth,error=str(e)))
for app in pyatspi.Registry.getDesktop(0):
 if app.name in ('kcmshell6','kaption'):walk(app)
print(json.dumps(rows,indent=2))
