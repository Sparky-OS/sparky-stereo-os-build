import json,os,socket,subprocess,sys,time,glob,shutil
d='/t/run'; shutil.rmtree(d,ignore_errors=True); os.makedirs(d+'/wl')
clip=d+'/clip.mkv'
subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=320x240:rate=25:duration=4','-c:v','libx264','-pix_fmt','yuv420p',clip],check=True)
try: os.setxattr(clip,'user.probe',b'1'); os.removexattr(clip,'user.probe'); print('fs supports user xattr')
except OSError as e: print('NO user xattr on this fs',e); sys.exit(2)
sock=d+'/ipc'
p=subprocess.Popen(['mpv','--no-config','--vo=null','--ao=null','--pause','--idle=no','--watch-later-directory='+d+'/wl','--input-ipc-server='+sock,clip],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
for _ in range(100):
    if os.path.exists(sock): break
    time.sleep(.1)
s=socket.socket(socket.AF_UNIX); s.connect(sock); f=s.makefile('rw')
def cmd(*a):
    f.write(json.dumps({'command':list(a)})+'\n'); f.flush()
    while True:
        r=json.loads(f.readline())
        if 'error' in r: return r
time.sleep(1.5)
def wl(): 
    lines=[]
    for fn in sorted(glob.glob(d+'/wl/*')):
        for l in open(fn).read().splitlines():
            if l.startswith('#') or not l.strip() or l.startswith('start='): continue
            lines.append(l)
    return ' | '.join(lines) if lines else '(no per-file options stored)'
def xa():
    try: return os.getxattr(clip,'user.stereo-policy.swap-eyes').decode()
    except OSError: return '(no xattr)'
out={}
out['toggle']=cmd('set_property','video-stereo-swap','yes')['error']
out['after_toggle_watchlater']=wl(); out['after_toggle_xattr']=xa()
r=cmd('video-stereo-store-swap'); out['store_command']=r['error']
out['after_store_watchlater']=wl(); out['after_store_xattr']=xa()
out['after_store_swap_prop']=cmd('get_property','video-stereo-swap').get('data'); out['after_store_swap_file_prop']=cmd('get_property','video-stereo-swap-file').get('data')
cmd('quit'); 
try: p.wait(5)
except Exception: p.kill()
print(json.dumps(out,indent=1))
