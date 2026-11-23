#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Model-free captiond protocol fixture, installed only in a disposable proof rig."""
import ctypes,json,os,selectors,signal,socket,subprocess,sys,time
from pathlib import Path
ctypes.CDLL(None).prctl(15,b'captiond',0,0,0)
if '--list-devices' in sys.argv:
 print('0 CPU CPU CPU');sys.exit(0)
args=sys.argv[1:];out=Path(os.environ['LC73_FIXTURE_OUT']);cfg=Path(args[args.index('--config')+1]).read_text();sockpath=args[args.index('--socket')+1]
mic='input=auto-source\n' in cfg
log=(out/'stand-in.jsonl').open('a',buffering=1)
def record(**data):log.write(json.dumps(dict(time=time.monotonic(),**data))+'\n')
record(event='start',argv=args,config=cfg,recognition='synthetic protocol fixture; no model opened',microphone=mic)
children=[]
for name,target,extra in [('lc73-output','captiond-test-sink','stream.capture.sink=true')]+([('lc73-input','captiond-test-source','node.dont-fallback=true')] if mic else []):
 props='{ node.name="'+name+'" '+extra+' adapter.auto-port-config={ mode=dsp } }'
 children.append(subprocess.Popen(['pw-record','--target',target,'--properties',props,'--raw','--rate','16000','--channels','1','/dev/null']))
server=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);server.bind(sockpath);server.listen();server.setblocking(False)
sel=selectors.DefaultSelector();sel.register(server,selectors.EVENT_READ);clients={};stopped=False

def stop(*_):
 global stopped
 stopped=True
signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
def status():
 mismatch=(out/'mismatch').exists()
 return dict(type='status',state='listening',engine='stub',model=Path(args[args.index('--model')+1]).name,language='en',detected='en',source='sink:captiond-test-sink',live=True,input='source:captiond-test-source' if mic else '',input_live=mic,input_mix=False,input_echo=False,gpu=mismatch,accelerator='Fixture wrong GPU' if mismatch else 'CPU',vad='',behind=(out/'behind').exists(),sounds=[],vocabulary='')
def send(client,data):
 try:client.sendall((json.dumps(data)+'\n').encode())
 except OSError:pass
n=0;nextcaption=time.monotonic();started=time.monotonic()
try:
 while not stopped:
  for key,_ in sel.select(.1):
   if key.fileobj is server:
    client,_=server.accept();client.setblocking(False);clients[client]=b'';sel.register(client,selectors.EVENT_READ);send(client,dict(type='hello',proto=1,daemon='captiond'));send(client,status())
   else:
    client=key.fileobj
    try:chunk=client.recv(65536)
    except OSError:chunk=b''
    if not chunk:sel.unregister(client);clients.pop(client);client.close();continue
    clients[client]+=chunk
    while b'\n' in clients[client]:
     line,clients[client]=clients[client].split(b'\n',1)
     event=json.loads(line);record(event='command',command=event)
     if event['type']=='get-status':send(client,status())
     elif event['type']=='list-sources':send(client,dict(type='sources',items=[]))
     elif event['type']=='list-models':send(client,dict(type='models',items=[dict(name=p.stem,path=str(p),size=p.stat().st_size,kind='speech') for p in Path('/home/builder/.local/share/captiond/models').glob('*.bin')],directory='/home/builder/.local/share/captiond/models'))
     elif event['type']=='ping':send(client,dict(type='pong'))
  if time.monotonic()>=nextcaption and (not (out/'kit-mode').exists() or ((out/'playback').exists() and float((out/'playback').read_text())>started)):
   n+=1;nextcaption=time.monotonic()+1
   phrase='The quick brown fox jumps over the lazy dog. '+str(n)
   event=dict(type='caption',id=n,committed=phrase,tentative='',lang='en',final=True,t0=n*1000,t1=n*1000+800,channel='output')
   for client in list(clients):send(client,event)
   record(event='caption',text=phrase)
finally:
 for child in children:child.terminate()
 for child in children:child.wait(timeout=10)
 for client in clients:client.close()
 server.close();Path(sockpath).unlink(missing_ok=True);record(event='stop',child_codes=[p.returncode for p in children])
