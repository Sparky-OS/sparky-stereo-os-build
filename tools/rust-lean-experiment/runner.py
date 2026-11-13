#!/usr/bin/env python3
"""An offline, resumable series of whole steps; no partial result is accepted."""
import argparse
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import signal
import threading
import time
from guard import atomic, guarded, machine


def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()


def checked(argv, **kwargs):
    return subprocess.run(argv,check=True,env=dict(os.environ,LC_ALL='C'),**kwargs)


def inventory(root):
    rows=[]
    for base,dirs,files in os.walk(root,followlinks=False):
        dirs[:]=sorted(dirs)
        for n in sorted(files+[d for d in dirs if (Path(base)/d).is_symlink()]):
            p=Path(base)/n;rel=p.relative_to(root).as_posix()
            rows.append({'path':rel,'link':os.readlink(p)} if p.is_symlink() else
                        {'path':rel,'mode':p.stat().st_mode&0o7777,'bytes':p.stat().st_size,'sha256':sha(p)})
    rows.sort(key=lambda r:r['path'])
    return hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def extract(archive,target,manifest):
    target.mkdir()
    with tarfile.open(archive) as tf:
        for m in tf:
            path=Path(m.name)
            if path.is_absolute() or '..' in path.parts or m.isdev() or m.isfifo():
                raise RuntimeError('unsafe archive member: '+m.name)
            if m.issym() and (Path(m.linkname).is_absolute() or '..' in Path(os.path.normpath(str(path.parent/m.linkname))).parts):
                raise RuntimeError('unsafe symbolic link '+m.name)
            if m.islnk():raise RuntimeError('hard links are not part of this source format')
        tf.extractall(target,filter='fully_trusted')
    expected=json.loads(manifest.read_text())['sha256']
    if inventory(target)!=expected:raise RuntimeError('extracted source manifest mismatch: '+str(archive))


class Runner:
    def __init__(self,root):
        self.root=root.resolve();self.plan=json.loads((root/'plan.json').read_text())
        self.statepath=root/'state.json';self.state=json.loads(self.statepath.read_text()) if self.statepath.exists() else {'completed':{},'images':{}}
        self.digest=sha(root/'plan.json')
        if self.state.get('plan_sha256',self.digest)!=self.digest:raise RuntimeError('plan changed since first run')
        self.state.update(plan_sha256=self.digest,version=self.plan['version'],pid=os.getpid())
        (root/'runtime').mkdir(exist_ok=True);(root/'results').mkdir(exist_ok=True)
        # The rootful Podman store is confined to this kit; no host compiler or apt writes.
        self.engine=self.plan.get('engine') or ['sudo','-n','podman','--root',str(root/'runtime/storage'),'--runroot',str(root/'runtime/runroot')]
        self.base=self.plan['image_id'];self.cpus=str(self.plan['cpus'])

    def save(self,**fields):self.state.update(fields,updated_unix=time.time());atomic(self.statepath,self.state)

    def verify_payload(self):
        for line in (self.root/'SHA256SUMS').read_text().splitlines():
            digest,name=line.split('  ',1)
            p=self.root/name
            if Path(name).is_absolute() or '..' in Path(name).parts or not p.is_file() or sha(p)!=digest:
                raise RuntimeError('kit checksum mismatch: '+name)
        expected= self.plan['seed_version']
        if expected!='1.98.1+dfsg1-1+stereo3d1+lc1':raise RuntimeError('plan names an unauthorized seed')
        machine()  # fail before starting anything when CPU telemetry is unavailable

    def floors(self):
        return {str(self.root):self.plan['scratch_floor_gib'],'/':12}

    def guard(self,name,argv,out):
        return guarded({'name':name,'engine':self.engine,'argv':argv,'output':str(out),
                        'floors_gib':self.floors(),'start_temperature_c':self.plan['start_temperature_c'],
                        'stop_temperature_c':self.plan['stop_temperature_c']})

    def container(self,name,image,mounts,command,user='1000:1000',remove=True):
        argv=[*self.engine,'run',*(['--rm'] if remove else []),'--name',name,'--network','none','--pull=never','--cpus',self.cpus,
              '--memory','8g','--ulimit','core=0','--cap-add','SYS_ADMIN','--cap-add','PERFMON','--user',user,
              '-e','LC_ALL=C','-e','PYTHONDONTWRITEBYTECODE=1','-e','RL541_CPUS='+self.cpus]
        if self.plan.get('fixture'):
            argv+=['-e','RL541_FIXTURE=1']
            if os.environ.get('RL541_FIXTURE_DELAY'):argv+=['-e','RL541_FIXTURE_DELAY='+os.environ['RL541_FIXTURE_DELAY']]
        for src,dst,ro in mounts:
            if ',' in str(src):raise RuntimeError('commas in bind paths are unsupported')
            argv+=['--mount','type=bind,src='+str(src)+',dst='+dst+(',readonly' if ro else '')]
        return [*argv,image,*command]

    def remove_owned(self,name):
        r=subprocess.run([*self.engine,'container','exists',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        # Docker's container exists is unsupported; fixture Docker uses inspect.
        if self.plan.get('fixture'):
            r=subprocess.run([*self.engine,'container','inspect',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        if r.returncode==0:checked([*self.engine,'rm','-f',name],stdout=subprocess.DEVNULL)
        elif r.returncode not in (1,125):raise RuntimeError('cannot inspect owned container '+name)

    def accepted(self,step):
        dest=self.root/'results'/step['id'];receipt=dest/'receipt.json'
        if not receipt.exists():return False
        r=json.loads(receipt.read_text())
        if r.get('complete') is not True or r['plan_sha256']!=self.digest or r['step']!=step:
            raise RuntimeError('result receipt does not match plan: '+step['id'])
        for n,h in r['files'].items():
            if sha(dest/n)!=h:raise RuntimeError('finished result changed: '+step['id']+'/'+n)
        if step['kind']=='install':
            image=r['runtime_image_id']
            checked([*self.engine,'image','inspect',image],stdout=subprocess.DEVNULL)
            self.state['images'][step['form']]=image
        self.state['completed'][step['id']]=r['completed_unix']
        return True

    def execute(self,step):
        sid=step['id'];name='rl541-'+sid
        self.remove_owned(name)
        work=self.root/'runtime/work';partial=self.root/'runtime/partial'
        for p in (work,partial):
            if p.exists():shutil.rmtree(p)
            p.mkdir()
        kind=step['kind'];script=self.root/'scripts';extra={}
        if kind=='load':
            # Image load happens from a local verified archive; no pull is permitted.
            with gzip.open(self.root/'image.tar.gz','rb') as f:
                p=subprocess.Popen([*self.engine,'load'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
                try:shutil.copyfileobj(f,p.stdin);p.stdin.close();log=p.stdout.read();rc=p.wait()
                except BaseException:p.kill();p.wait();raise
            (partial/'load.log').write_bytes(log)
            if rc:raise RuntimeError('image load failed')
            checked([*self.engine,'image','inspect',self.base],stdout=subprocess.DEVNULL)
        elif kind in ('whole','check'):
            form=step['form'];sources=self.root/'sources'
            extract(sources/(form+'.tar.gz'),work/'tree',sources/(form+'.manifest.json'))
            # The readonly reference is independent from the build's configured tree.
            extract(sources/(form+'.tar.gz'),work/'form',sources/(form+'.manifest.json'))
            if form=='A':authored=work/'form'
            else:
                extract(sources/'A.tar.gz',work/'authored',sources/'A.manifest.json');authored=work/'authored'
            mounts=[(script,'/scripts',True),(work,'/work',False),(work/'form','/form',True),(authored,'/authored',True)]
            argv=self.container(name,self.base,mounts,['python3','/scripts/build_step.py',kind,self.cpus])
            extra['guard']=self.guard(name,argv,partial/'guard')
            shutil.move(work/'result',partial/'result')
        elif kind=='install':
            packages=self.root/'results'/step['build']/'result/packages'
            argv=self.container(name,self.base,[(script,'/scripts',True),(packages,'/packages',True)],
                                ['python3','/scripts/install_step.py'],user='0:0',remove=False)
            extra['guard']=self.guard(name,argv,partial/'guard')
            image=checked([*self.engine,'commit',name,'rl541-runtime-'+self.digest[:12]+'-'+step['form'].lower()],stdout=subprocess.PIPE,text=True).stdout.strip()
            checked([*self.engine,'image','inspect',image],stdout=subprocess.DEVNULL)
            extra['runtime_image_id']=image;self.state['images'][step['form']]=image
            checked([*self.engine,'rm',name],stdout=subprocess.DEVNULL)
        elif kind=='runtime':
            image=self.state['images'][step['form']]
            mounts=[(script,'/scripts',True),(work,'/work',False),(self.root/'subject','/subject',True)]
            extra['guard']=self.guard(name,self.container(name,image,mounts,
                ['python3','/scripts/runtime_step.py',step['task']]),partial/'guard')
            shutil.move(work/'result',partial/'result')
        elif kind=='analyze':
            mounts=[(script,'/scripts',True),(self.root/'results','/results',True),
                    (self.root/'sources','/sources',True),(work,'/work',False)]
            extra['guard']=self.guard(name,self.container(name,self.base,mounts,
                ['python3','/scripts/analyze.py']),partial/'guard')
            shutil.move(work/'result',partial/'result')
        elif kind=='summary':
            from summary import summarize
            summarize(self.root,self.plan)
            shutil.copytree(self.root/'summary',partial/'result')
        else:raise RuntimeError('unknown step '+kind)
        result={'complete':True,'version':self.plan['version'],'plan_sha256':self.digest,'step':step,
                'form_checksum':self.plan.get('forms',{}).get(step.get('form')),
                'completed_unix':time.time(),'machine':machine(),'files':{},**extra}
        for p in partial.rglob('*'):
            if p.is_file():result['files'][p.relative_to(partial).as_posix()]=sha(p)
        atomic(partial/'receipt.json',result)
        destination=self.root/'results'/sid
        if destination.exists():shutil.rmtree(destination)
        partial.rename(destination)
        # A result is made durable before the build tree is retired or the state advances.
        shutil.rmtree(work)
        self.state['completed'][sid]=result['completed_unix'];self.save(active=None)

    def run(self):
        lock=(self.root/'runtime/worker.lock').open('w')
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        self.save(status='verifying',active=None)
        stopping=threading.Event()
        def disk_watch():
            while not stopping.is_set():
                for path,floor in self.floors().items():
                    free=shutil.disk_usage(path).free
                    with (self.root/'runtime/disk.jsonl').open('a') as f:
                        f.write(json.dumps({'unix':time.time(),'path':path,'free_bytes':free})+'\n')
                    if free<(floor+5)*1024**3:
                        (self.root/'runtime/space-stop.txt').write_text('floor plus 5 GiB crossed: '+path)
                        os.kill(os.getpid(),signal.SIGTERM);return
                stopping.wait(5)
        def interrupted(signum,frame):raise RuntimeError('worker interrupted; unfinished step is not counted')
        signal.signal(signal.SIGTERM,interrupted)
        thread=threading.Thread(target=disk_watch,daemon=True);thread.start()
        try:
            self.verify_payload()
            for step in self.plan['steps']:
                if self.accepted(step):self.save();continue
                if (self.root/'pause.request').exists():self.save(status='paused',active=None);return
                self.save(status='running',active=step['id'])
                self.execute(step)
            self.save(status='complete',active=None)
        except BaseException as e:
            self.save(status='blocked',error=str(e));raise
        finally:
            stopping.set();thread.join(timeout=6)


def status(root):
    path=root/'state.json'
    if not path.exists():print('not started');return
    s=json.loads(path.read_text());print(json.dumps(s,indent=2,sort_keys=True))


if __name__=='__main__':
    os.environ['LC_ALL']='C'
    p=argparse.ArgumentParser();p.add_argument('action',choices=['worker','status']);p.add_argument('root',type=Path);a=p.parse_args()
    if a.action=='worker':Runner(a.root).run()
    else:status(a.root)
