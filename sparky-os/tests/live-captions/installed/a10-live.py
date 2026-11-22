#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Private-account A10 live measurement worker; called by a10-kit.py, not directly."""
import hashlib,json,os,re,signal,socket,subprocess,sys,time,urllib.request
from pathlib import Path
WORDS='the quick brown fox jumps over the lazy dog'

def known(text):
    return WORDS in ' '.join(re.findall(r"[a-z]+",str(text).lower()))

def temperature(root=Path('/sys/class/hwmon')):
    errors=[]
    for directory in sorted(root.glob('hwmon*')):
        try:
            if (directory/'name').read_text().strip()!='k10temp':continue
            return dict(celsius=int((directory/'temp1_input').read_text())/1000,source=str(directory/'temp1_input'))
        except (OSError,ValueError) as e:errors.append(str(e))
    return dict(celsius=None,warning='Temperature unavailable: '+('; '.join(errors) or 'no readable k10temp temp1_input'))

def digest(path):
    with Path(path).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def run(args,check=True):
    return subprocess.run(list(map(str,args)),text=True,capture_output=True,check=check,timeout=150)

def wait(label,test,bound=120):
    start=time.monotonic();last=None
    while time.monotonic()-start<bound:
        try:
            last=test()
            if last:return last
        except (OSError,ValueError,subprocess.SubprocessError) as e:last=str(e)
        time.sleep(.1)
    raise RuntimeError(label+' not ready within '+str(bound)+' seconds: '+str(last))

def cpu_ticks():
    value=0
    for name in ('captiond','kaption'):
        for pid in run(['pgrep','-u',str(os.getuid()),'-x',name],False).stdout.split():
            try:
                fields=Path('/proc/'+pid+'/stat').read_text().rsplit(')',1)[1].split()
                value+=int(fields[11])+int(fields[12])
            except (OSError,ValueError,IndexError):pass
    return value

def http(base,path,data=None,content='application/json',method=None):
    if isinstance(data,dict):data=json.dumps(data).encode()
    req=urllib.request.Request(base+path,data=data,headers={'Content-Type':content},method=method)
    with urllib.request.urlopen(req,timeout=180) as response:return json.load(response)

def multipart(wav):
    boundary='lc73-a10-known-clip'
    value=('--'+boundary+'\r\nContent-Disposition: form-data; name="file"; filename="fox.wav"\r\nContent-Type: audio/wav\r\n\r\n').encode()+wav.read_bytes()
    for key,text in [('language','en'),('response_format','json'),('threads','4')]:
        value+=('\r\n--'+boundary+'\r\nContent-Disposition: form-data; name="'+key+'"\r\n\r\n'+text).encode()
    return value+('\r\n--'+boundary+'--\r\n').encode(),'multipart/form-data; boundary='+boundary

def session(config):
    out=Path(config['output']);out.mkdir(parents=True,exist_ok=False)
    children=[];rows=[];active=False
    def save(name,value):(out/name).write_text(json.dumps(value,indent=2)+'\n')
    def row(name,expected,found,ok=True):
        rows.append(dict(row=name,expected=expected,found=found,passed=bool(ok),load=Path('/proc/loadavg').read_text().strip()))
        save('rows.json',rows);print(name+'\t'+expected+'\t'+str(found),flush=True)
        if not ok:raise RuntimeError(name+': '+str(found))
    def spawn(args,name):
        f=(out/(name+'.log')).open('w')
        child=subprocess.Popen(args,stdout=f,stderr=subprocess.STDOUT,start_new_session=True);children.append(child);return child
    def action(*args):return run(['sparky-stereo-live-captions',*args])
    def status():return json.loads(action('status').stdout)
    def gone():
        return all(run(['pgrep','-u',str(os.getuid()),'-x',name],False).returncode==1 for name in ('captiond','kaption')) and not list(Path(os.environ['XDG_RUNTIME_DIR']).glob('sparky-stereo-live-captions/session-*/captiond.sock'))
    try:
        if config.get('boot'):
            os.environ.update(QT_QPA_PLATFORM='wayland',QT_QUICK_BACKEND='software',LIBGL_ALWAYS_SOFTWARE='1',PIPEWIRE_PROPS='{ adapter.auto-port-config = { mode = dsp } }',QT_LINUX_ACCESSIBILITY_ALWAYS_ON='1',XDG_CURRENT_DESKTOP='KDE',KDE_FULL_SESSION='true',XDG_SESSION_TYPE='wayland',WAYLAND_DISPLAY='lc73-bench')
            run(['systemctl','--user','stop','pipewire.socket','pipewire.service','wireplumber.service'],False)
            spawn(['pipewire'],'pipewire');spawn(['wireplumber'],'wireplumber')
            wait('private PipeWire registry',lambda:run(['pw-dump'],False).returncode==0)
            spawn(['kwin_wayland','--virtual','--no-lockscreen','--no-global-shortcuts','--no-kactivities','--socket','lc73-bench','--width','1920','--height','1080'],'kwin')
            wait('private Wayland socket',lambda:(Path(os.environ['XDG_RUNTIME_DIR'])/'lc73-bench').is_socket())
            # Retry an actual D-Bus response; do not infer readiness from a sleep.
            wait('KWin D-Bus',lambda:run(['gdbus','call','--session','--dest','org.kde.KWin','--object-path','/KWin','--method','org.kde.KWin.supportInformation'],False).returncode==0)
            run(['systemctl','--user','import-environment','WAYLAND_DISPLAY','QT_QPA_PLATFORM','QT_QUICK_BACKEND','PIPEWIRE_PROPS','DBUS_SESSION_BUS_ADDRESS','QT_LINUX_ACCESSIBILITY_ALWAYS_ON'])
            run(['dbus-update-activation-environment','--systemd','WAYLAND_DISPLAY','QT_QPA_PLATFORM','QT_LINUX_ACCESSIBILITY_ALWAYS_ON'])
        inventory=json.loads(run(['sparky-stereo-gpu-env','--list','--json']).stdout);save('graphics.json',inventory)
        cards=['cpu'] if config.get('fixture') else ['cpu']+[x['id'] for x in inventory if x.get('vendor')=='AMD' and x.get('canRender')]
        row('card inventory','CPU and two Radeon choices' if not config.get('fixture') else 'fixture CPU only',cards,len(cards)==(1 if config.get('fixture') else 3))
        cat=json.loads(Path('/usr/share/sparky-stereo/live-captions/models.json').read_text())
        for entry in cat:
            if entry['id'] not in ('tiny','base'):continue
            model=Path.home()/'.local/share/captiond/models'/entry['file']
            before=digest(model);identity=(model.stat().st_dev,model.stat().st_ino)
            row(entry['id']+'/file','verified size and digest',dict(bytes=model.stat().st_size,sha256=before),before==entry['sha256'] and model.stat().st_size==entry['bytes'])
            action('select',entry['id']);action('microphone','off');action('login','off')
            store=json.loads((Path.home()/'.local/share/github.com.thewh1teagle.vibe/app_config.json').read_text())
            row(entry['id']+'/shared selection','same absolute file in native Vibe and Partners choices',store.get('model.path'),store.get('model.path')==str(model) and status()['model']==str(model))
            for card in cards:
                for trial in range(config.get('trials',3)):
                    name=entry['id']+'-'+card.replace(':','_')+'-'+str(trial+1);folder=out/name;folder.mkdir()
                    run(['sparky-stereo-partners','card',card]);action('on');active=True
                    sock=wait('integration socket',lambda:next(iter(Path(os.environ['XDG_RUNTIME_DIR']).glob('sparky-stereo-live-captions/session-*/captiond.sock')),None))
                    connection=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);connection.settimeout(.1);connection.connect(str(sock));connection.sendall(b'{"type":"get-status"}\n{"type":"list-models"}\n')
                    events=[];pending=b'';ready=None;listing=None
                    def read():
                        nonlocal pending,ready,listing
                        try:chunk=connection.recv(65536)
                        except socket.timeout:return
                        if not chunk:raise RuntimeError('caption socket closed')
                        pending+=chunk
                        while b'\n' in pending:
                            line,pending=pending.split(b'\n',1);event=json.loads(line);events.append(dict(received=time.monotonic(),event=event))
                            if event.get('type')=='status' and event.get('state')=='listening':ready=event
                            if event.get('type')=='models':listing=event
                    def prepared():
                        read();return ready and listing and run(['pgrep','-u',str(os.getuid()),'-x','kaption'],False).returncode==0
                    wait('daemon listening and Kaption',prepared)
                    row(name+'/captiond listing','same selected file in native list',listing,str(model) in json.dumps(listing))
                    run(['captionctl','--socket',str(sock),'set-source','sink:captiond-test-sink'])
                    read();startindex=len(events)
                    listener=spawn([sys.executable,str(Path(__file__).with_name('atspi-listen.py')),str(folder/'atspi.jsonl')],name+'-atspi')
                    wait('AT-SPI listener file',lambda:(folder/'atspi.jsonl').exists())
                    start=time.monotonic();ticks=cpu_ticks();drain=None;final=None;visible=None;samples=[]
                    if config.get('fixture'):(Path(os.environ['LC73_FIXTURE_OUT'])/'playback').write_text(str(start))
                    player=spawn(['pw-play','--target','captiond-test-sink','--properties','{ node.name = lc73-bench-player adapter.auto-port-config = { mode = dsp } }','/usr/share/captiond/testing/fox.wav'],name+'-audio')
                    (folder/'graph-before.json').write_text(run(['pw-dump']).stdout)
                    def link(source,target):
                        result=run(['pw-link',source,target],False)
                        return result.returncode==0 or 'File exists' in result.stderr
                    wait('private clip left link',lambda:link('lc73-bench-player:output_MONO','captiond-test-sink:playback_FL'))
                    wait('private clip right link',lambda:link('lc73-bench-player:output_MONO','captiond-test-sink:playback_FR'))
                    capture='lc73-output' if config.get('fixture') else 'captiond'
                    wait('private monitor capture link',lambda:link('captiond-test-sink:monitor_FL',capture+':input_MONO'))
                    (folder/'graph-linked.json').write_text(run(['pw-dump']).stdout)
                    deadline=start+90
                    while time.monotonic()<deadline:
                        read();now=time.monotonic()
                        if player.poll() is not None and drain is None:
                            if player.returncode:raise RuntimeError('known clip playback failed')
                            drain=now
                        for event in events[startindex:]:
                            v=event['event']
                            if v.get('type')=='caption' and v.get('final') and known(v.get('committed','')):final=event;break
                        for line in (folder/'atspi.jsonl').read_text().splitlines():
                            try:v=json.loads(line)
                            except ValueError:continue
                            if v.get('time',0)>=start and known(v.get('data','')):visible=v;break
                        if not samples or now-samples[-1]['time']>=1:
                            t=temperature(Path(config['hwmon'])) if config.get('fixture') else temperature();samples.append(dict(time=now,temperature=t,cpu_ticks=cpu_ticks(),load=Path('/proc/loadavg').read_text().strip()))
                            if t['celsius'] is not None and t['celsius']>=62:raise RuntimeError('A10 temperature reached 62 C; stopped')
                        if drain and final and visible:break
                    elapsed=time.monotonic()-start
                    result=dict(model=str(model),card=card,trial=trial+1,daemon_status=ready,playback_start=start,playback_drain=drain,caption=final,kaption_announcement=visible,cpu_percent_one_core=100*(cpu_ticks()-ticks)/os.sysconf('SC_CLK_TCK')/elapsed,samples=samples,synthetic=bool(config.get('fixture')))
                    if drain and final:result['settled_caption_lag_s']=final['received']-drain
                    if drain and visible:result['visible_caption_lag_s']=visible['time']-drain
                    (folder/'events.json').write_text(json.dumps(events,indent=2));(folder/'result.json').write_text(json.dumps(result,indent=2))
                    connection.close();listener.terminate();listener.wait(timeout=10)
                    row(name+'/known words','known clip words in final daemon caption AND Kaption announcement',dict(final=bool(final),visible=bool(visible),lag=result.get('visible_caption_lag_s')),bool(drain and final and visible))
                    warning=next((x['temperature'].get('warning') for x in samples if x['temperature'].get('warning')),None)
                    if warning:print(name+' temperature: '+warning,flush=True)
                    action('off');active=False;wait('pair stopped',gone)
                    row(name+'/off','no pair or socket',gone())
            # Vibe's own loaded-model listing and transcription, using the identical file.
            server=spawn(['vibe-server','serve','--host','127.0.0.1','--port','0'],entry['id']+'-vibe')
            def address():
                for line in (out/(entry['id']+'-vibe.log')).read_text().splitlines():
                    try:v=json.loads(line)
                    except ValueError:continue
                    if v.get('status')=='ready' and v.get('port'):return 'http://127.0.0.1:'+str(v['port'])
            base=wait('Vibe server readiness',address)
            load={'path':str(model),'gpu_device':-1,'no_gpu':True};loaded=http(base,'/v1/models/load',load)
            models=http(base,'/v1/models');save(entry['id']+'-vibe-list.json',dict(request=load,response=loaded,models=models))
            row(entry['id']+'/Vibe listing','selected basename returned by Vibe',models,any(x.get('id')==model.name for x in models.get('data',[])))
            body,content=multipart(Path('/usr/share/captiond/testing/fox.wav'))
            transcript=http(base,'/v1/audio/transcriptions',body,content);save(entry['id']+'-vibe-transcript.json',transcript)
            row(entry['id']+'/Vibe words','exact known clip words',transcript,known(transcript.get('text','')))
            http(base,'/v1/models',method='DELETE');server.terminate();server.wait(timeout=30)
            row(entry['id']+'/one file','same inode, checksum and one pathname; neither program copied it',dict(path=str(model),inode=identity,sha256=digest(model)),digest(model)==before and identity==(model.stat().st_dev,model.stat().st_ino) and model.stat().st_nlink==1)
        return 0
    finally:
        if active:action('off')
        for child in reversed(children):
            if child.poll() is None:
                os.killpg(child.pid,signal.SIGTERM)
                try:child.wait(timeout=15)
                except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait()
        save('rows.json',rows)
        save('cleanup.json',dict(pair_gone=gone(),children_stopped=all(p.poll() is not None for p in children)))

if __name__=='__main__':
    cfg=json.loads(Path(sys.argv[1]).read_text())
    fixture=cfg.get('fixture') and Path('/.dockerenv').exists() and os.environ.get('LC73_KIT_FIXTURE')=='1'
    if not fixture and 'A10-9600P' not in Path('/proc/cpuinfo').read_text():raise SystemExit('Recognition is guarded to the A10 bench.')
    try:raise SystemExit(session(cfg))
    except Exception as error:print('FAIL:',error,flush=True);raise
