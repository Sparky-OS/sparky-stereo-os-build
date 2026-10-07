import socket, json, time, subprocess, sys, os
vf = sys.argv[2]
p = subprocess.Popen(['mpv','--no-config','--ao=null','--vo=image','--vo-image-outdir=/v/out','--vo-image-format=png','--input-ipc-server=/tmp/s','--keep-open=yes','--pause','--hwdec=no','--msg-level=all=info','--vf='+vf, sys.argv[1]], stdout=open('/v/out/mpv.log','w'), stderr=subprocess.STDOUT)
time.sleep(4)
s = socket.socket(socket.AF_UNIX); s.connect('/tmp/s'); s.settimeout(3)
def cmd(*a):
    s.sendall((json.dumps({'command': list(a)}) + '\n').encode()); time.sleep(.5)
    try: print(a, s.recv(65536).decode().strip().splitlines()[-1])
    except Exception as e: print('no reply', e)
cmd('frame-step'); time.sleep(.7)
cmd(*json.loads(sys.argv[3])); time.sleep(.7)
cmd('get_property','vf')
p.terminate()
