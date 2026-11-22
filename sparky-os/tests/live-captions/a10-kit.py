#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""A10 bench only: a10-kit.py STAGE NEW_OUTPUT --download-models [--vibe-stage DIR].
Run as root after review. Never invoked on the station. Installs only additions,
uses a disposable account/private virtual session, removes additions/downloads.
The separate a10-live.py worker is exercised with protocol stand-ins in the rig.
"""
import argparse,ctypes,hashlib,json,os,pwd,re,shlex,shutil,signal,subprocess,sys,time,urllib.request
from pathlib import Path
sys.dont_write_bytecode=True
class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,url):
        if not url.startswith('https://'):raise ValueError('Non-HTTPS redirect refused')
        return super().redirect_request(req,fp,code,msg,headers,url)
HTTP=urllib.request.build_opener(HTTPSRedirect())

def digest(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def fetch(item,dest):
    print('DOWNLOAD',item['url'],item['bytes'],'bytes SHA256',item['sha256'],flush=True)
    if not re.fullmatch('[0-9a-f]{64}',item['sha256']) or not item['url'].startswith('https://'):raise ValueError('Verified HTTPS input required')
    count=0;h=hashlib.sha256()
    with HTTP.open(urllib.request.Request(item['url'],headers={'Accept-Encoding':'identity'}),timeout=120) as response,dest.open('xb') as output:
        while chunk:=response.read(1024*1024):
            count+=len(chunk)
            if count>item['bytes']:raise ValueError('Input exceeds declared size')
            output.write(chunk);h.update(chunk)
    if count!=item['bytes'] or h.hexdigest()!=item['sha256']:raise ValueError('Input checksum or size mismatch: '+str(dest))

def text(args,**kw):return subprocess.check_output(list(map(str,args)),text=True,**kw)
def states():
    return {p:(v,s) for p,v,s in (x.split('\t') for x in text(['dpkg-query','-W','-f=${binary:Package}\t${Version}\t${db:Status-Status}\n']).splitlines()) if s!='not-installed'}
def planned(plan,prefix='Inst '):return [x.split()[1] for x in plan.splitlines() if x.startswith(prefix)]
def safe_additions(plan,before):
    if planned(plan,'Remv '):raise RuntimeError('Install would remove existing packages; refused')
    candidate=planned(plan)
    if any(p in before or p+':amd64' in before for p in candidate):raise RuntimeError('Install would replace an existing package/state; refused')
    return candidate

def wait(label,check):
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        if check():return
        time.sleep(.2)
    raise RuntimeError(label+' not ready within 120 seconds')
def run(args,**kw):return subprocess.run(list(map(str,args)),check=True,text=True,**kw)
def index_record(uri,size):
    filename=urllib.parse.unquote(uri.rsplit('/',1)[1]);package=filename.split('_')[0];matches=[]
    for stanza in text(['apt-cache','show',package]).split('\n\n'):
        fields=dict(line.split(': ',1) for line in stanza.splitlines() if ': ' in line and not line.startswith(' '))
        if fields.get('Filename','').rsplit('/',1)[-1]==filename and fields.get('Size')==str(size) and re.fullmatch('[0-9a-f]{64}',fields.get('SHA256','')):matches.append(fields['SHA256'])
    if len(set(matches))!=1:raise RuntimeError('No unique signed apt-index SHA256 for '+uri)
    return dict(url=uri,bytes=size,sha256=matches[0])

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('stage',type=Path);parser.add_argument('output',type=Path);parser.add_argument('--vibe-stage',type=Path);parser.add_argument('--download-models',action='store_true');args=parser.parse_args()
    if 'A10-9600P' not in Path('/proc/cpuinfo').read_text() or Path('/.dockerenv').exists():parser.error('Real recognition is restricted to the A10 bench, outside containers.')
    if os.geteuid()!=0:parser.error('Run this reviewed kit as root for reversible package/account cleanup.')
    if not args.download_models:parser.error('Use --download-models to explicitly choose the two catalogue downloads.')
    ctypes.CDLL(None).prctl(15,b'lc73-a10-kit',0,0,0)
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False);out.chmod(0o755)
    work=out/'scratch';work.mkdir();work.chmod(0o755);cache=work/'apt-cache';cache.mkdir()
    before=states();auto=set(text(['apt-mark','showauto']).split());new=[];account=None;uid=None;rc=1;errors=[]
    env=dict(os.environ,DEBIAN_FRONTEND='noninteractive')
    def save(name,value):(out/name).write_text(json.dumps(value,indent=2)+'\n')
    save('packages-before.json',before);save('automatic-before.json',sorted(auto))
    def interrupted(*_):raise KeyboardInterrupt('Termination requested; cleaning kit additions')
    signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
    apt=['apt-get','-y','--no-install-recommends','-o','Dir::Cache::archives='+str(cache)]
    try:
        targets=[]
        names=['captiond','libcaptiond-client0','kaption','kaption-common','sparky-stereo-partners','sparky-stereo-live-captions']
        for folder in [args.stage]+([args.vibe_stage] if args.vibe_stage else []):
            sums={x.split(None,1)[1].lstrip('* '):x.split()[0] for x in (folder/'SHA256SUMS').read_text().splitlines()}
            for name in names+(['vibe'] if folder==args.vibe_stage else []):
                paths=list(folder.glob(name+'_*.deb'))
                if not paths:continue
                if len(paths)!=1 or digest(paths[0])!=sums.get(paths[0].name):raise RuntimeError('Staged archive mismatch: '+name)
                targets.append(str(paths[0].resolve()))
        if len([x for x in targets if Path(x).name.split('_')[0] in names])!=len(names):raise RuntimeError('Need all six staged runtime packages')
        targets+=['vibe','python3-gi','python3-pyatspi','pipewire-bin','wireplumber','dbus-user-session','kwin-wayland','libglib2.0-bin']
        plan=text(apt+['--simulate','install']+targets,env=env);(out/'install-plan.txt').write_text(plan)
        new=safe_additions(plan,before)
        uris=text(apt+['--print-uris','install']+targets,env=env);(out/'input-uris.txt').write_text(uris);inputs=[]
        for line in uris.splitlines():
            if not line.startswith("'"):continue
            uri,filename,size,*_=shlex.split(line)
            if uri.startswith('file:'):continue  # staged files already checked above
            item=index_record(uri,int(size));inputs.append(item)
            fetch(item,cache/filename)
        save('package-downloads.json',inputs)
        if planned(text(apt+['--simulate','install']+targets,env=env))!=new:raise RuntimeError('Package plan changed')
        with (out/'apt-install.log').open('w') as log:run(['unshare','--net']+apt+['--no-download','install']+targets,env=env,stdout=log,stderr=subprocess.STDOUT)
        save('packages-during.json',states())
        account='lc73b'+hashlib.sha256(str(out).encode()).hexdigest()[:8]
        try:pwd.getpwnam(account);raise RuntimeError('Temporary account already exists; refused')
        except KeyError:pass
        home=work/'home';run(['useradd','--create-home','--home-dir',str(home),'--shell','/bin/bash',account]);uid=pwd.getpwnam(account).pw_uid
        for group in ('render','video'):
            if subprocess.run(['getent','group',group],stdout=subprocess.DEVNULL).returncode==0:run(['usermod','-a','-G',group,account])
        modeldir=home/'.local/share/captiond/models';modeldir.mkdir(parents=True)
        catalogue=json.loads(Path('/usr/share/sparky-stereo/live-captions/models.json').read_text());save('model-downloads.json',catalogue)
        for item in catalogue:
            if item['id'] in ('tiny','base'):fetch(item,modeldir/item['file'])
        pw=home/'.config/pipewire/pipewire.conf.d';pw.mkdir(parents=True)
        (pw/'90-lc73.conf').write_text('context.objects = [ { factory = adapter args = { factory.name = support.null-audio-sink node.name = captiond-test-sink media.class = Audio/Sink audio.position = [ FL FR ] adapter.auto-port-config = { mode = dsp monitor = true position = preserve } } } ]\n')
        wp=home/'.config/wireplumber/wireplumber.conf.d';wp.mkdir(parents=True)
        (wp/'90-lc73.conf').write_text('wireplumber.profiles = { main = { monitor.alsa = disabled monitor.bluez = disabled monitor.bluez-midi = disabled } }\n')
        for parent,dirs,files in os.walk(home):
            os.chown(parent,uid,uid)
            for filename in files:os.chown(Path(parent)/filename,uid,uid)
        # Only the newly created user's manager is touched.
        run(['loginctl','enable-linger',account]);run(['systemctl','start','user@'+str(uid)+'.service'])
        wait('private user bus',lambda:(Path('/run/user')/str(uid)/'bus').is_socket())
        result=out/'measurements';config=work/'session.json';config.write_text(json.dumps(dict(output=str(result),boot=True,trials=3)))
        os.chown(out,uid,uid)
        command=['runuser','-u',account,'--','env','-i','PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','USER='+account,'LOGNAME='+account,'HOME='+str(home),'XDG_RUNTIME_DIR=/run/user/'+str(uid),'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/'+str(uid)+'/bus','LANG=C.UTF-8','OMP_NUM_THREADS=4',sys.executable,str(Path(__file__).with_name('a10-live.py')),str(config)]
        with (out/'live.log').open('w') as log:
            child=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            try:rc=child.wait(timeout=3600)
            finally:
                if child.poll() is None:
                    os.killpg(child.pid,signal.SIGTERM)
                    try:child.wait(timeout=30)
                    except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait()
    finally:
        if account and uid is not None:
            for command in (['loginctl','disable-linger',account],['loginctl','terminate-user',account],['systemctl','stop','user@'+str(uid)+'.service'],['userdel',account]):
                r=subprocess.run(command,text=True,capture_output=True)
                if r.returncode:errors.append(' '.join(command)+': '+r.stderr.strip())
        try:
            now=states();remove=[p for p in new if p in now or p+':amd64' in now]
            if remove:
                plan=text(['apt-get','--simulate','purge']+remove,env=env);(out/'remove-plan.txt').write_text(plan)
                actual={x.split(':')[0] for prefix in ('Remv ','Purg ') for x in planned(plan,prefix)}
                if not actual<={x.split(':')[0] for x in remove}:raise RuntimeError('Cleanup would remove a pre-existing package; refused')
                with (out/'apt-remove.log').open('w') as log:run(['apt-get','-y','purge']+remove,env=env,stdout=log,stderr=subprocess.STDOUT)
            after=states();save('packages-after.json',after)
            if after!=before:raise RuntimeError('Package state not restored exactly')
            current=set(text(['apt-mark','showauto']).split())
            if auto-current:run(['apt-mark','auto']+sorted(auto-current))
            if current-auto:run(['apt-mark','manual']+sorted(current-auto))
        except Exception as error:errors.append(str(error))
        shutil.rmtree(work);save('cleanup.json',dict(downloads_removed=not work.exists(),errors=errors))
    print('cleanup\toriginal packages, no account or downloads\t'+str(errors or 'restored'))
    return rc if not errors else 1
if __name__=='__main__':raise SystemExit(main())
