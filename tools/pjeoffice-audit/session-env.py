# SPDX-License-Identifier: GPL-3.0-or-later
import os
from pathlib import Path
import sys
for p in Path('/proc').glob('[0-9]*/comm'):
 try:
  if p.read_text().strip() != 'plasmashell': continue
  session=dict(v.split(b'=',1) for v in (p.parent/'environ').read_bytes().split(b'\0') if b'=' in v)
  env=os.environ.copy()
  for key in ['DISPLAY','WAYLAND_DISPLAY','XAUTHORITY']:
   value=session.get(key.encode())
   if value is not None: env[key]=value.decode()
  env['PJ18_SESSION_ENV']='1'
  os.execve('/bin/bash',['bash',sys.argv[1]],env)
 except (FileNotFoundError,PermissionError): continue
raise SystemExit('No readable plasmashell environment in this private container')
