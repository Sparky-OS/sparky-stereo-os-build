#!/usr/bin/env python3
"""Recheck retained evidence and rebuild the model-free rig in NEW_OUTPUT.

Only NEW_OUTPUT is written on the host. Docker creates temporary lc73-rerun-*
objects through this lane's socket, then removes those exact objects. Optional
LC73_PACKAGE_CACHE names a read-only folder of previously verified debs.
Requires the recorded local base image; no image is pulled. No model is acquired.
"""
import argparse,hashlib,json,os,shutil,struct,subprocess,sys,urllib.request,zlib
from pathlib import Path

class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        if not newurl.startswith('https://'):raise ValueError('Non-HTTPS redirect refused')
        return super().redirect_request(req,fp,code,msg,headers,newurl)
HTTP=urllib.request.build_opener(HTTPSRedirect())

LANE=Path(os.environ.get('LC73_LANE',str(Path(__file__).resolve().parent.parent))).resolve()
SCRIPTS=LANE/'scripts'
BASE='gpu-route-346a-base:testing-20261020'
ENV=dict(os.environ,DOCKER_HOST='unix:///K3D/partners/queue/live-captions-73/docker.sock',PYTHONDONTWRITEBYTECODE='1')
rows=[]
def row(name,expected,found,ok=True):
    rows.append(dict(row=name,expected=expected,found=found,passed=bool(ok)))
    print(name+'\t'+expected+'\t'+str(found).replace('\n',' / ').replace('\t',' '),flush=True)
    if not ok:raise RuntimeError(name+': '+str(found))
def run(args,**kw):return subprocess.run([str(x) for x in args],check=True,env=ENV,**kw)
def text(args):return subprocess.check_output([str(x) for x in args],text=True,env=ENV).strip()
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        while data:=f.read(1024*1024):h.update(data)
    return h.hexdigest()
def sums(folder,name='SHA256SUMS'):
    count=0
    for line in (folder/name).read_text().splitlines():
        want,rel=line.split(None,1);p=(folder/rel.lstrip('* ')).resolve()
        if not p.is_relative_to(folder.resolve()):raise ValueError('Checksum path escapes folder')
        if digest(p)!=want:raise ValueError('Checksum mismatch: '+str(p))
        count+=1
    return count
def stereo(p):
    b=p.read_bytes();assert b[:8]==b'\x89PNG\r\n\x1a\n';i=8;marks=[];size=None
    while i<len(b):
        n=struct.unpack('>I',b[i:i+4])[0];kind=b[i+4:i+8];data=b[i+8:i+8+n];crc=struct.unpack('>I',b[i+8+n:i+12+n])[0]
        assert zlib.crc32(kind+data)==crc,(p,kind)
        if kind==b'IHDR':size=struct.unpack('>II',data[:8])
        if kind==b'sTER':marks.append(data)
        i+=n+12
    assert size==(3840,1080) and marks==[b'\x01'],(p,size,marks)
def evidence(out):
    row('staged closure','all SHA-256 match',str(sums(LANE/'stage'))+' files')
    row('proof inputs','all SHA-256 match',str(sums(LANE/'evidence'))+' files')
    shutil.copytree(LANE/'evidence/nodes',out/'saved-nodes')
    with (out/'saved-node-check.json').open('w') as f:run([sys.executable,SCRIPTS/'check-nodes.py',out/'saved-nodes'],stdout=f)
    row('saved PipeWire routing','separate sink and microphone; pause closes both','pass')
    for gpu in ('amd','nvidia'):
        for scale in ('100','125'):
            name=gpu+'-'+scale;p=out/('saved-'+name);p.mkdir()
            for case in ('desktop','video'):
                for file in (case+'.pns','windows-'+case+'.json'):shutil.copyfile(LANE/'evidence/proof'/name/file,p/file)
                stereo(p/(case+'.pns'))
            with (p/'analysis.log').open('w') as f:run([sys.executable,SCRIPTS/'analyze-eyes.py',p,str(int(scale)/100)],stdout=f)
            actual=json.loads((p/'eye-measurements.json').read_text())
            row('saved '+name,'two aligned glyph pairs, recorded -2 px',str([(r['left_minus_right_px'],r['glyph_xor_pixels']) for r in actual]),all(r['left_minus_right_px']==-2 and r['glyph_xor_pixels']==0 for r in actual))
    witness=json.loads((LANE/'evidence/sharing/result.json').read_text())
    row('shared path witness','retained native listings, no recognition',witness)

INSTALL=r'''set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
apt-get --yes --allow-downgrades --no-install-recommends install /out/debs/*.deb
getent passwd 1000 >/dev/null || useradd --create-home --uid 1000 --shell /bin/bash builder
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\t${Status}\n' > /out/installed.tsv
systemctl --global is-enabled captiond.service captiond.socket > /out/activation.txt || [ "$?" = 1 ]
find /etc/systemd/user /home/builder -type l -name '*caption*' -print > /out/activation-links.txt
pgrep -x captiond > /out/daemon-before-start.txt && exit 9 || [ "$?" = 1 ]
cmake -S /proof/fixture-src -B /out/rig-tools -G Ninja
cmake --build /out/rig-tools -j4
mkdir -p /out/fixtures
/usr/bin/ffmpeg -nostdin -y -hide_banner -loglevel error -threads 2 -filter_threads 2 -filter_complex_threads 2 -f lavfi -i color=c=0x406060:s=1920x1080:r=1 -f lavfi -i color=c=0x604060:s=1920x1080:r=1 -filter_complex '[0:v][1:v]hstack=inputs=2' -t 3 -c:v ffv1 -level 3 -metadata:s:v:0 stereo_mode=left_right /out/fixtures/stereo.mkv
chown -R 1000:1000 /out/rig-tools /out/fixtures
'''
class Rig:
    def __init__(self,out):
        self.out=out;self.prefix='lc73-rerun-'+hashlib.sha256(str(out).encode()).hexdigest()[:12];self.containers=[];self.image=None
    def create(self,label,image,command,options=(),mounts=()):
        name=self.prefix+'-'+label
        args=['docker','create','--name',name,'--pull=never','--platform','linux/amd64','--cpus','4','--ulimit','core=1','--network','none']+list(options)
        for src,dest,ro in [(SCRIPTS,'/proof',True)]+list(mounts):args+=['--mount',f'type=bind,source={src},target={dest}'+(',readonly' if ro else '')]
        cid=text(args+[image]+command);self.containers.append(name)
        with (self.out/'.container-ids').open('a') as f:f.write(cid+'\n')
        with (self.out/(label+'.log')).open('w') as f:run(['docker','start','-a',name],stdout=f,stderr=subprocess.STDOUT)
        rc=text(['docker','inspect','-f','{{.State.ExitCode}}',name]);row(label,'container exit 0',rc,rc=='0')
        return name
    def cleanup(self):
        for name in reversed(self.containers):
            if text(['docker','inspect','-f','{{.State.Running}}',name])=='true':run(['docker','stop','-t','5',name],stdout=subprocess.DEVNULL)
            run(['docker','rm',name],stdout=subprocess.DEVNULL)
        if self.image:run(['docker','rmi',self.image],stdout=subprocess.DEVNULL)

def live(out):
    want=(LANE/'evidence/rerun-base-image.txt').read_text().strip();actual=text(['docker','image','inspect','-f','{{.Id}}',BASE]);row('base image',want,actual,want==actual)
    manifest=json.loads((LANE/'evidence/rerun-packages.json').read_text());debs=out/'debs';debs.mkdir()
    cache=Path(os.environ['LC73_PACKAGE_CACHE']).resolve() if os.environ.get('LC73_PACKAGE_CACHE') else None
    # Network acquisition is complete before any program-under-test container exists.
    for m in manifest:
        dest=debs/m['file'];source=m['source'];local=None
        if source.startswith('stage/'):local=LANE/source
        elif cache and (cache/m['file']).is_file():local=cache/m['file']
        elif source.startswith('https://repo.sparkyos.org/'):
            candidate=Path('/var/lib/sparky-lanes/sparky-repo-r1118a')/source.removeprefix('https://repo.sparkyos.org/')
            if candidate.is_file():local=candidate
        print('input\t'+str(m['bytes'])+' bytes\t'+source,flush=True)
        if local:shutil.copyfile(local,dest)
        else:
            if not source.startswith('https://'):raise ValueError('Refusing non-HTTPS source')
            with HTTP.open(source,timeout=60) as response,dest.open('wb') as f:
                if not response.url.startswith('https://'):raise ValueError('Refusing non-HTTPS redirect')
                total=0
                while chunk:=response.read(1024*1024):
                    total+=len(chunk)
                    if total>m['bytes']:raise ValueError('Archive exceeds declared size')
                    f.write(chunk)
        if dest.stat().st_size!=m['bytes'] or digest(dest)!=m['sha256']:raise ValueError('Archive mismatch: '+source)
    (out/'download-inputs.json').write_text(json.dumps(manifest,indent=2)+'\n')
    row('package inputs','recorded exact size and checksum',str(len(manifest))+' verified archives')
    rig=Rig(out)
    try:
        name=rig.create('install',BASE,['bash','-c',INSTALL],mounts=[(out,'/out',False),(Path('/K3D/partners/https-only-apt.sh'),'/run/https-only-apt.sh',True),(Path('/etc/ssl/certs/ca-certificates.crt'),'/run/host-ca.crt',True)])
        expected=json.loads((LANE/'evidence/rerun-installed.json').read_text());installed={}
        for l in (out/'installed.tsv').read_text().splitlines():
            p,v,a,status=l.split('\t',3)
            if status=='install ok installed':installed[p]=[v,a]
        differences={p:[v,installed.get(p)] for p,v in expected.items() if installed.get(p)!=v}
        row('installed versions','all recorded rig versions',differences or 'exact',not differences)
        row('install activation','service/socket disabled; no links or daemon', (out/'activation.txt').read_text().strip(),(out/'activation.txt').read_text().split()==['disabled','disabled'] and not (out/'activation-links.txt').read_text().strip() and not (out/'daemon-before-start.txt').read_text().strip())
        rig.image=rig.prefix+':verified';text(['docker','commit',name,rig.image])
        nodes=out/'nodes';nodes.mkdir()
        rig.create('nodes',rig.image,['/proof-bin/capture-nodes','/out'],['--user','1000:1000'],[(out/'rig-tools','/proof-bin',True),(nodes,'/out',False)])
        with (out/'nodes.json').open('w') as f:run([sys.executable,SCRIPTS/'check-nodes.py',nodes],stdout=f)
        row('fresh PipeWire routing','independent output/input; pause closes both','pass')
        for gpu in ('amd','nvidia'):
            for scale in ('1','1.25'):
                label=gpu+'-'+scale.replace('.','-');p=out/label;p.mkdir()
                device='/dev/dri/renderD128' if gpu=='amd' else 'nvidia.com/gpu=0'
                rig.create(label,rig.image,['dbus-run-session','--','bash','/proof/rig-session.sh','/out',scale,'captions'],['--user','1000:1000','--group-add','125','--cap-add','SYS_NICE','--device',device,'-e','QT_LOGGING_RULES=kwin_*.debug=true'],[(out/'rig-tools','/proof-bin',True),(out/'fixtures','/fixtures',True),(p,'/out',False)])
                with (p/'analysis.log').open('w') as f:run([sys.executable,SCRIPTS/'analyze-eyes.py',p,scale],stdout=f)
                for r in json.loads((p/'eye-measurements.json').read_text()):
                    stereo(p/(r['case']+'.pns'))
                    row(label+'/'+r['case'],'baseline -2 px; matching glyphs; KWin layer 9',str((r['left_minus_right_px'],r['glyph_xor_pixels'],r['window']['layer'])),r['left_minus_right_px']==-2 and r['glyph_xor_pixels']==0 and r['window']['layer']==9)
                atspi=(p/'atspi.jsonl').read_text();row(label+'/AT-SPI','settled fox announcement','present' if 'object:announcement' in atspi and 'quick brown fox' in atspi else 'missing','object:announcement' in atspi and 'quick brown fox' in atspi)
    finally:rig.cleanup()
    row('temporary Docker objects','removed by exact name','removed')

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('output',type=Path);parser.add_argument('--evidence-only',action='store_true');args=parser.parse_args();out=args.output.resolve()
    if out.exists():parser.error('output must not exist')
    if ',' in str(out):parser.error('Docker bind paths cannot contain commas')
    out.mkdir(parents=True);print('row\texpected\tfound',flush=True);ok=False
    try:
        evidence(out)
        if not args.evidence_only:live(out)
        ok=True
    except Exception as e:
        print('FAIL\tall rows match\t'+str(e),flush=True);rows.append(dict(row='failure',expected='all rows match',found=str(e),passed=False))
    finally:(out/'rows.json').write_text(json.dumps(rows,indent=2)+'\n')
    return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
