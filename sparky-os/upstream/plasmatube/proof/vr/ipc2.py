import socket, json, time, subprocess, sys
vf = sys.argv[2]; yaws = sys.argv[3].split(',')
p = subprocess.Popen(['mpv','--no-config','--ao=null','--vo=null','--input-ipc-server=/tmp/s','--keep-open=yes','--hwdec=no','--vf='+vf, sys.argv[1]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)
s = socket.socket(socket.AF_UNIX); s.connect('/tmp/s'); s.settimeout(3)
def cmd(*a):
    s.sendall((json.dumps({'command': list(a)}) + '\n').encode()); time.sleep(.6); 
    try: s.recv(65536)
    except Exception: pass
for i, y in enumerate(yaws):
    cmd('vf-command','vr','yaw',y,'v360'); time.sleep(.8)
    cmd('screenshot-to-file','/v/out/y%d.png' % i)
p.terminate()
