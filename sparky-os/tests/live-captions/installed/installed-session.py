#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
import json,os,signal,socket,subprocess,sys,time,traceback
from pathlib import Path
from gi.repository import Gio,GLib
out=Path(sys.argv[1]);scale=sys.argv[2];language=sys.argv[3]
os.environ.update(HOME='/home/builder',XDG_RUNTIME_DIR='/run/user/1000',DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus',XDG_CURRENT_DESKTOP='KDE',KDE_FULL_SESSION='true',KDE_SESSION_VERSION='6',XDG_SESSION_TYPE='wayland',QT_FORCE_STDERR_LOGGING='1',QT_LINUX_ACCESSIBILITY_ALWAYS_ON='1',KWIN_SCREENSHOT_NO_PERMISSION_CHECKS='1',KWIN_WAYLAND_NO_PERMISSION_CHECKS='1',KWIN_VIRTUAL_STEREO_MODES='1',LC73_FIXTURE_OUT=str(out),LANG=('pt_BR.UTF-8' if language=='pt_BR' else 'C.UTF-8'),LANGUAGE=language)
os.environ.pop('LC_ALL',None)
children=[];rows=[]
def run(args,check=True):return subprocess.run(args,capture_output=True,text=True,check=check,timeout=150)
def spawn(args,name):
 f=(out/(name+'.log')).open('w');p=subprocess.Popen(args,stdout=f,stderr=subprocess.STDOUT,start_new_session=True);children.append(p);return p

def wait(label,test,bound=120):
 start=time.monotonic();last=None
 (out/'readiness.jsonl').open('a').write(json.dumps(dict(condition=label,bound_seconds=bound,monotonic=start,load=Path('/proc/loadavg').read_text().strip()))+'\n')
 while time.monotonic()-start<bound:
  try:
   last=test()
   if last:return last
  except Exception as e:last=str(e)
  time.sleep(.25)
 raise RuntimeError(label+' not ready in '+str(bound)+'s: '+str(last))
def row(name,expected,found,ok=True):
 rows.append(dict(row=name,expected=expected,found=found,passed=bool(ok),load=Path('/proc/loadavg').read_text().strip()));(out/'rows.json').write_text(json.dumps(rows,indent=2)+'\n');print(name+'\t'+expected+'\t'+str(found),flush=True)
 if not ok:raise RuntimeError(name)
def status():return json.loads(run(['sparky-stereo-live-captions','status']).stdout)
def pw(name):
 data=json.loads(run(['pw-dump']).stdout);(out/(name+'.json')).write_text(json.dumps(data,indent=2)+'\n');return [v['info']['props']['node.name'] for v in data if v.get('type')=='PipeWire:Interface:Node' and v.get('info',{}).get('props',{}).get('node.name','').startswith('lc73-')]
if not Path('/run/user/1000/bus').exists():
 spawn(['dbus-daemon','--session','--nofork','--address=unix:path=/run/user/1000/bus'],'session-bus')
 wait('session bus',lambda:Path('/run/user/1000/bus').is_socket())
bus=Gio.bus_get_sync(Gio.BusType.SESSION,None)
def support():
 return bus.call_sync('org.kde.KWin','/KWin','org.kde.KWin','supportInformation',None,GLib.VariantType('(s)'),Gio.DBusCallFlags.NONE,2000,None).unpack()[0]
try:
 (out/'load-before.txt').write_text(Path('/proc/loadavg').read_text())
 initial=status();row('installed off','off, login false, microphone false',{k:initial[k] for k in ('on','login','microphone')},not any(initial[k] for k in ['on','login','microphone']))
 spawn(['kwin_wayland','--virtual','--no-lockscreen','--no-global-shortcuts','--no-kactivities','--socket','lc73','--width','1920','--height','1080'],'kwin')
 wait('Wayland socket',lambda:Path('/run/user/1000/lc73').is_socket());os.environ.update(WAYLAND_DISPLAY='lc73',QT_QPA_PLATFORM='wayland')
 (out/'kwin-support.txt').write_text(wait('KWin D-Bus supportInformation',support))
 outputs=json.loads(run(['kscreen-doctor','-j']).stdout)['outputs'][0];modes=outputs['modes'];modes=modes.values() if isinstance(modes,dict) else modes
 mode=next(m for m in modes if m.get('stereo3D')==1 and m['size']=={'width':1920,'height':1080})
 run(['kscreen-doctor','output.'+outputs['name']+'.mode.'+mode['id'],'output.'+outputs['name']+'.scale.'+scale]);(out/'outputs.json').write_text(run(['kscreen-doctor','-j']).stdout)
 run(['systemctl','--user','import-environment','WAYLAND_DISPLAY','QT_QPA_PLATFORM','DBUS_SESSION_BUS_ADDRESS','LC73_FIXTURE_OUT','LANG','LANGUAGE','QT_LINUX_ACCESSIBILITY_ALWAYS_ON'])
 run(['dbus-update-activation-environment','--systemd','WAYLAND_DISPLAY','QT_QPA_PLATFORM','XDG_RUNTIME_DIR','HOME','XDG_CURRENT_DESKTOP','KDE_FULL_SESSION','KDE_SESSION_VERSION','XDG_SESSION_TYPE','LC73_FIXTURE_OUT','LANG','LANGUAGE','QT_LINUX_ACCESSIBILITY_ALWAYS_ON'])
 run(['systemctl','--user','stop','pipewire.socket','pipewire.service'],False)
 spawn(['pipewire'],'pipewire')
 spawn(['wireplumber'],'wireplumber')
 wait('private PipeWire registry',lambda:run(['pw-dump'],False).returncode==0)
 row('off streams','no caption streams',pw('off-streams'),not pw('off-streams'))
 spawn(['/usr/lib/x86_64-linux-gnu/libexec/kactivitymanagerd'],'activities')
 spawn(['plasmashell','--no-respawn'],'plasma')
 spawn(['python3','/proof/atspi-listen.py',str(out/'atspi.jsonl')],'atspi')
 page=spawn(['kcmshell6','kcm_sparkystereo_partners'],'page')
 run(['systemctl','--user','daemon-reload'])
 words=initial['labels']
 def tree(name):
  text=json.dumps(json.loads(run(['python3','/proof/atspi-tree.py']).stdout),ensure_ascii=False,indent=2);(out/(name+'.json')).write_text(text);return text
 def click(key):
  result=run(['python3','/proof/page-act.py',words[key]]);(out/'page-actions.jsonl').open('a').write(result.stdout)
 def refresh():click('refresh')
 def gone():
  return not any(run(['pgrep','-x',name],False).returncode==0 for name in ('captiond','kaption')) and not list(Path('/run/user/1000/sparky-stereo-live-captions').glob('session-*'))
 def off(name):
  click('off');wait('stopped children/socket',gone);wait('stopped streams',lambda:not pw(name));result=run(['systemctl','--user','show','sparky-stereo-live-captions.service','--property=Result','--value']).stdout.strip();row(name,'no pair/socket/stream; unit Result=success',result,result=='success')
 wait('installed page',lambda:words['on'] in tree('page-'+language))
 page_tree=tree('page-'+language)
 row('page '+language,'translated caption switch, privacy and model labels',words['on'],all(words[k] in page_tree for k in ('on','privacy','model','microphone','login')))
 run(['python3','/proof/capture.py',str(out/'page.png')]);run(['python3','/proof/mark_pns.py',str(out/'page.png'),str(out/'page.pns')])
 run(['systemctl','--user','start','lc73-session.target']);row('login initially off','graphical target does not start captions',status()['on'],not status()['on'])
 player=spawn(['mpv','--no-config','--no-audio','--loop-file=inf','--fullscreen','--input-ipc-server=/run/user/1000/lc73-mpv','--vo=gpu-next','--gpu-context=wayland','/fixtures/stereo.mkv'],'mpv')
 # Actual audio playback into the private null sink; fixture captions are synthetic.
 audio=spawn(['bash','-c','while pw-play --target=captiond-test-sink /usr/share/captiond/testing/fox.wav; do :; done'],'audio')
 click('on')
 wait('paired session',lambda:all(run(['pgrep','-x',name],False).returncode==0 for name in ('captiond','kaption')))
 wait('actual route',lambda:'Recognition is using CPU.' in status()['message'] or 'O reconhecimento está usando CPU.' in status()['message'])
 row('page starts pair','captiond and Kaption in the installed unit',run(['systemctl','--user','show','sparky-stereo-live-captions.service','--property=ControlGroup']).stdout.strip())
 wait('known sentence at AT-SPI',lambda:'quick brown fox jumps over the lazy dog' in (out/'atspi.jsonl').read_text())
 row('known caption words','The quick brown fox jumps over the lazy dog.','exact known sentence received through AT-SPI; synthetic')
 wait('output stream',lambda:pw('output-only')==['lc73-output'])
 row('microphone initially untouched','output capture only',pw('output-only'),pw('output-only')==['lc73-output'])
 # Verify playback and the declared stereo clip before retaining the exact frame.
 def video_ready():
  snap=json.loads(run(['python3','/proof/kwin_windows.py',str(out/'kwin.log')]).stdout)
  return any('mpv' in w.get('cls','').lower() and w.get('fs') for w in snap.get('windows',[]))
 wait('full-screen playing clip',video_ready)
 def position():
  with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as sock:
   sock.settimeout(2);sock.connect('/run/user/1000/lc73-mpv');sock.sendall(b'{"command":["get_property","time-pos"]}\n');stream=sock.makefile()
   while True:
    data=json.loads(stream.readline())
    if 'error' in data:return data.get('data')
 first=wait('mpv playback time',lambda:position());second=wait('mpv time advancing',lambda:([p] if (p:=position()) is not None and p!=first else False));row('clip playing','mpv playback time advances',[first,second],player.poll() is None)
 playback=pw('playing-streams');nodes=json.loads((out/'playing-streams.json').read_text());playing=[n['info']['props'] for n in nodes if n.get('type')=='PipeWire:Interface:Node' and n.get('info',{}).get('props',{}).get('application.name')=='pw-play'];row('known audio playing','private sink playback stream',playing,bool(playing))
 run(['python3','/proof/capture-visible.py',str(out),'video',scale]);run(['python3','/proof/mark_pns.py',str(out/'video.png'),str(out/'video.pns')])
 os.killpg(player.pid,signal.SIGTERM);player.wait(timeout=15);os.killpg(audio.pid,signal.SIGTERM);audio.wait(timeout=15)
 run(['python3','/proof/capture-visible.py',str(out),'desktop',scale]);run(['python3','/proof/mark_pns.py',str(out/'desktop.png'),str(out/'desktop.pns')])
 (out/'behind').touch();wait('measured lag message',lambda:status()['message']==words['slow']);refresh();row('cannot keep up said','localized measured-behind sentence',status()['message'],words['slow'] in tree('slow-message'));(out/'behind').unlink()
 refresh();off('off-cleanup')
 click('microphone');wait('microphone choice saved',lambda:status()['microphone']);click('on');wait('microphone stream',lambda:sorted(pw('microphone-on'))==['lc73-input','lc73-output']);row('microphone chosen','separate output and input streams',pw('microphone-on'));refresh();off('microphone-off-cleanup');click('microphone');wait('microphone choice cleared',lambda:not status()['microphone'])
 click('login');wait('login enabled',lambda:status()['login']);row('login enabled only by choice','enabled, not running',(status()['login'],status()['on']),status()['login'] and not status()['on'])
 run(['systemctl','--user','stop','lc73-session.target','graphical-session.target']);run(['systemctl','--user','start','lc73-session.target']);wait('chosen login start',lambda:run(['pgrep','-x','kaption'],False).returncode==0);row('chosen login start','graphical target starts pair','pair started');refresh();off('login-off-cleanup');click('login');wait('login disabled',lambda:not status()['login']);run(['systemctl','--user','stop','lc73-session.target','graphical-session.target']);run(['systemctl','--user','start','lc73-session.target']);row('login disabled again','no pair',gone(),gone())
 personal=Path('/home/builder/.local/share/github.com.thewh1teagle.vibe/app_config.json');saved=personal.read_bytes();personal.write_bytes(saved+b' ');changed=personal.read_bytes()
 click('on');wait('changed-file refusal',lambda:json.loads((Path.home()/'.local/state/sparky-stereo-live-captions/status.json').read_text())['key']=='changed');wait('refused session gone',gone);refresh();expected=words['changed'].format(str(personal));row('changed file said and preserved','translated refusal and identical changed bytes',status()['message'],status()['message']==expected and personal.read_bytes()==changed and expected in tree('changed-message'));personal.write_bytes(saved)
 (out/'mismatch').touch();click('on');wait('route refusal',lambda:json.loads((Path.home()/'.local/state/sparky-stereo-live-captions/status.json').read_text())['key']=='route');wait('mismatch session gone',gone);refresh();expected=words['route'].format('CPU','Fixture wrong GPU');row('route mismatch said','translated mismatch; no pair',status()['message'],status()['message']==expected and expected in tree('route-message'));(out/'mismatch').unlink()
 row('final cleanup','disabled; no pair, socket or stream',dict(login=status()['login'],gone=gone(),streams=pw('final-streams')),not status()['login'] and gone() and not pw('final-streams'))
except Exception as e:
 rowdata=dict(row='execution',expected='complete',found=str(e),passed=False);rows.append(rowdata);(out/'rows.json').write_text(json.dumps(rows,indent=2)+'\n');traceback.print_exc();sys.exitcode=1
finally:
 run(['systemctl','--user','stop','sparky-stereo-live-captions.service'],False)
 for p in reversed(children):
  if p.poll() is None:os.killpg(p.pid,signal.SIGTERM)
 for p in reversed(children):
  try:p.wait(timeout=10)
  except subprocess.TimeoutExpired:p.kill();p.wait()
 (out/'load-after.txt').write_text(Path('/proc/loadavg').read_text())
sys.exit(getattr(sys,'exitcode',0))
