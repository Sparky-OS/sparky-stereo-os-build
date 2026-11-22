#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rerun milestone 2 in NEW_OUTPUT only; explicit local inputs in --config JSON.
No speech model. Serial network-disabled containers, four CPUs, named cleanup.
"""
import argparse,hashlib,json,os,shlex,shutil,struct,subprocess,sys,zlib
from pathlib import Path
sys.dont_write_bytecode=True

def digest(path):
    with Path(path).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def stereo(p):
    data=p.read_bytes();assert data[:8]==b'\x89PNG\r\n\x1a\n';i=8;marks=[];size=None
    while i<len(data):
        n=struct.unpack('>I',data[i:i+4])[0];kind=data[i+4:i+8];body=data[i+8:i+8+n]
        assert zlib.crc32(kind+body)==struct.unpack('>I',data[i+8+n:i+12+n])[0]
        if kind==b'IHDR':size=struct.unpack('>II',body[:8])
        if kind==b'sTER':marks.append(body)
        i+=12+n
    assert size==(3840,1080) and marks==[b'\x01'],(size,marks)
def depth_status(value):
    if value['glyph_xor_pixels']!=0 or value['window']['layer']!=9:return 'FAIL'
    if value['left_minus_right_px']==0:return 'PASS'
    return 'WAIT-822' if value['left_minus_right_px']==-2 else 'FAIL'

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('output',type=Path);ap.add_argument('--config',type=Path,default=Path(__file__).resolve().parent.parent/'milestone-inputs.json');a=ap.parse_args()
    out=a.output.resolve();cfg=json.loads(a.config.read_text())
    if out.exists():ap.error('Output must not exist')
    if any(x in str(out) for x in (',','\n')):ap.error('Unsupported bind path')
    out.mkdir(parents=True);(out/'input-config.json').write_bytes(a.config.read_bytes())
    env=dict(os.environ,DOCKER_HOST=cfg['docker_host'],PYTHONDONTWRITEBYTECODE='1')
    scripts=Path(cfg['scripts']);repo=Path(cfg['recipe_repo']);stage=Path(cfg['stage']);rows=[];waits=[];containers=[];images=[]
    prefix='lc73-whole-'+hashlib.sha256(str(out).encode()).hexdigest()[:10]
    def text(args):return subprocess.check_output(list(map(str,args)),env=env,text=True).strip()
    def run(args,log,extra=None):
        with Path(log).open('w') as f:r=subprocess.run(list(map(str,args)),env=dict(env,**(extra or {})),stdout=f,stderr=subprocess.STDOUT)
        if r.returncode:raise RuntimeError(str(args[0])+' exited '+str(r.returncode)+'; '+str(log))
    def row(name,expected,found,ok=True):
        rows.append(dict(row=name,expected=expected,found=found,passed=bool(ok),load=Path('/proc/loadavg').read_text().strip()))
        print(name+'\t'+expected+'\t'+str(found).replace('\n',' / '),flush=True)
        (out/'rows.json').write_text(json.dumps(rows,indent=2)+'\n')
        if not ok:raise RuntimeError(name)
    def create(label,image,command,mounts=(),options=()):
        name=prefix+'-'+label
        args=['docker','create','--name',name,'--pull=never','--platform','linux/amd64','--cpus','4','--ulimit','core=1','--network','none']+list(options)
        for src,dest,ro in [(scripts,'/proof',True)]+list(mounts):args+=['--mount','type=bind,src='+str(src)+',dst='+dest+(',readonly' if ro else '')]
        cid=text(args+[image]+command);containers.append(name)
        with (out/'.container-ids').open('a') as f:f.write(cid+'\n')
        run(['docker','start','-a',name],out/(label+'.log'))
        rc=text(['docker','inspect','-f','{{.State.ExitCode}}',name]);row(label,'container exit 0',rc,rc=='0')
        return name
    print('row\texpected\tfound',flush=True)
    try:
        for image,want in cfg['images'].items():row('input '+image,'recorded immutable image',text(['docker','image','inspect','-f','{{.Id}}',image]),text(['docker','image','inspect','-f','{{.Id}}',image])==want)
        row('source','clean order73 source',text(['git','-C',repo,'rev-parse','HEAD']),not text(['git','-C',repo,'status','--porcelain']))
        for name,folder in [('stage',stage),('scripts',scripts)]:
            count=0
            for line in (folder/'SHA256SUMS').read_text().splitlines():
                expected,relative=line.split(None,1);p=(folder/relative.lstrip('* ')).resolve()
                if not p.is_relative_to(folder.resolve()) or digest(p)!=expected:raise RuntimeError(name+' checksum '+relative)
                count+=1
            row(name+' checksums','every listed SHA256 matches',count)
        records=[]
        for p in stage.glob('*.sparky-build.json'):
            record=json.loads(p.read_text());assert record['recipeDirty'] is False and record['unrecorded']==[]
            records.append(dict(source=record['source'],commit=record['recipeCommit'],version=record['version']))
        row('source closures','four clean build records',records,len(records)==4)
        helpers=out/'helpers';helpers.mkdir()
        # Unchanged recipe/gates; only the launcher's local ledger path is relocated.
        build=(scripts/'build-continuation.sh').read_text().replace(cfg['lane']+'/.container-ids',str(out/'.container-ids'))
        (helpers/'build.sh').write_text(build)
        for package in ('sparky-stereo-partners','sparky-stereo-live-captions'):
            target=out/('build-'+package)
            run(['bash',helpers/'build.sh',package,target],out/(package+'-launcher.log'))
            record=json.loads(next(target.glob('*.sparky-build.json')).read_text())
            row(package+' gates','unchanged gates pass, recipeDirty false',dict(commit=record['recipeCommit'],dirty=record['recipeDirty']),not record['recipeDirty'] and record['unrecorded']==[])
        checkscript='set -e; python3 -B /recipe/tests/test_adapter.py; python3 -B /proof/test-a10-kit.py; cmake -S /proof/fixture-src -B /out/rig-tools -G Ninja; cmake --build /out/rig-tools -j4; chown -R 1000:1000 /out/rig-tools'
        create('source-and-kit-checks',cfg['build_image'],['bash','-c',checkscript],[(repo/'sparky-os/packages/sparky-stereo-live-captions','/recipe',True),(out,'/out',False)])
        log=(out/'source-and-kit-checks.log').read_text();row('model-free controls','17 adapter and 5 kit negative tests pass',log.count('\nOK\n'),log.count('\nOK\n')==2 and 'Ran 17 tests' in log and 'Ran 5 tests' in log)
        lc=out/'lifecycle';lc.mkdir()
        create('package-lifecycle',cfg['lifecycle_image'],['bash','/proof/package-lifecycle.sh'],[(cfg['archive'],'/archive',True),(cfg['published'],'/published',True),(cfg['row70'],'/row70',True),(cfg['vibe_stage'],'/vibe-stage',True),(stage,'/stage',True),(lc,'/out',False)])
        for file,prefixword,names in [('upgrade-plan.txt','Inst ',{'sparky-stereo-partners','sparky-stereo-live-captions'}),('remove-plan.txt','Remv ',{'sparky-stereo-partners','sparky-stereo-live-captions'})]:
            lines=[x for x in (lc/file).read_text().splitlines() if x.startswith(prefixword)]
            row(file,'actual apt '+prefixword.strip()+' for both packages',lines,{x.split()[1] for x in lines}==names)
        row('removal preserves personal files','five identical hash records',json.loads((lc/'personal-after.json').read_text()),(lc/'personal-before.json').read_bytes()==(lc/'personal-after.json').read_bytes())
        prep='set -e; dpkg -i /stage/libcaptiond-client0_0.1.0-1+lc1_amd64.deb /stage/captiond_0.1.0-1+lc1_amd64.deb /stage/kaption-common_0.1.0-1+lc1_all.deb /stage/kaption_0.1.0-1+lc1_amd64.deb /stage/sparky-stereo-partners_0.1.3+lc1_amd64.deb /stage/sparky-stereo-live-captions_0.1.0+lc1_all.deb; dpkg-query -W > /out/installed.tsv'
        name=create('install',cfg['lifecycle_image'],['bash','-c',prep],[(stage,'/stage',True),(out,'/out',False)])
        image=prefix+':installed';text(['docker','commit',name,image]);images.append(image)
        nodes=out/'native-nodes';nodes.mkdir()
        create('native-pipewire',image,['/proof-bin/capture-nodes','/out'],[(out/'rig-tools','/proof-bin',True),(nodes,'/out',False)],['--user','1000:1000'])
        run([sys.executable,'-B',scripts/'check-nodes.py',nodes],out/'native-nodes.json');row('native PipeWire','separate monitor/input; pause closes both','pass')
        for gpu in ('amd','nvidia'):
            for scale,language in [('1','en'),('1.25','pt_BR')]:
                label=gpu+'-'+scale;target=out/label
                helper=(scripts/'run-installed.sh').read_text().replace('lc73-installed3:verified',image).replace('>> "$lane/.container-ids"','>> '+shlex.quote(str(out/'.container-ids')))
                # Names vary with this output; helper removes exact names in its EXIT trap.
                helper=helper.replace('name=lc73-installed-${gpu}-${scale//./-}', 'name='+prefix+'-${gpu}-${scale//./-}')
                (helpers/'installed.sh').write_text(helper)
                run(['bash',helpers/'installed.sh',gpu,scale,language,target],out/(label+'-launcher.log'),{'LC73_KIT_FIXTURE':'1' if (gpu,scale)==('amd','1') else '0'})
                actual=json.loads((target/'session/rows.json').read_text())
                for x in actual:row(label+'/'+x['row'],x['expected'],x['found'],x['passed'])
                if (gpu,scale)==('amd','1'):
                    kitrows=json.loads((target/'session/kit-results/rows.json').read_text())
                    for x in kitrows:row('kit/'+x['row'],x['expected'],x['found'],x['passed'])
                    row('kit cleanup','no pair and all helper processes stopped',json.loads((target/'session/kit-results/cleanup.json').read_text()),all(json.loads((target/'session/kit-results/cleanup.json').read_text()).values()))
                run([sys.executable,'-B',scripts/'analyze-eyes.py',target/'session',scale],target/'eye-analysis.txt')
                for value in json.loads((target/'session/eye-measurements.json').read_text()):
                    stereo(target/'session'/(value['case']+'.pns'));status=depth_status(value);result=dict(row=label+'/'+value['case']+' caption depth',expected='0 px; glyph XOR 0; layer 9',found=[value['left_minus_right_px'],value['glyph_xor_pixels'],value['window']['layer']],status=status)
                    if status=='WAIT-822':waits.append(result)
                    else:row(result['row'],result['expected'],result['found'],status=='PASS')
        row('depth exception negative control','only known -2/zero-XOR/layer9 can wait; other faults fail',[depth_status(dict(left_minus_right_px=x,glyph_xor_pixels=0,window={'layer':9})) for x in (0,-2,2)], [depth_status(dict(left_minus_right_px=x,glyph_xor_pixels=0,window={'layer':9})) for x in (0,-2,2)]==['PASS','WAIT-822','FAIL'] and depth_status(dict(left_minus_right_px=-2,glyph_xor_pixels=1,window={'layer':9}))=='FAIL')
        import csv
        strings=list(csv.DictReader((scripts.parent/'translations/sentences-en-pt_BR.tsv').open(),delimiter='\t'))
        row('sentence handoff','30 unique keys, English and pt_BR',len(strings),len(strings)==30 and len({v['key'] for v in strings})==30 and all(v['en'] and v['pt_BR'] for v in strings))
        for patch,tree in cfg['placement_checks']:
            run(['git','-C',tree,'apply','--check',patch],out/(Path(patch).name+'.log'));row('placement '+Path(patch).name,'patch applies without changing tree','pass')
    except BaseException as error:
        rows.append(dict(row='execution',expected='complete',found=str(error),passed=False));print('FAIL\tcomplete\t'+str(error),flush=True)
    finally:
        for name in reversed(containers):
            subprocess.run(['docker','stop','-t','10',name],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            r=subprocess.run(['docker','rm',name],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
            if r.returncode:rows.append(dict(row='cleanup '+name,expected='removed',found=r.stderr,passed=False))
        for image in reversed(images):
            r=subprocess.run(['docker','rmi',image],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
            if r.returncode:rows.append(dict(row='cleanup '+image,expected='removed',found=r.stderr,passed=False))
        (out/'rows.json').write_text(json.dumps(rows,indent=2)+'\n');(out/'waiting-822.json').write_text(json.dumps(waits,indent=2)+'\n')
        print('\nWAITING FOR ROW 822 — these rows remain red against zero:',flush=True)
        for x in waits:print(x['row']+'\t'+x['expected']+'\t'+str(x['found']),flush=True)
        (out/'rows.tsv').write_text('row\texpected\tfound\tpassed\n'+''.join(x['row']+'\t'+x['expected']+'\t'+json.dumps(x['found'],ensure_ascii=False)+'\t'+str(x['passed'])+'\n' for x in rows))
        (out/'waiting-822.tsv').write_text('row\texpected\tfound\tstatus\n'+''.join(x['row']+'\t'+x['expected']+'\t'+str(x['found'])+'\tWAIT-822\n' for x in waits))
        success=bool(rows) and all(x['passed'] for x in rows);(out/'exit.txt').write_text(('0' if success else '1')+'\n')
        print('RESULT\tall ordinary rows pass\t'+('PASS' if success else 'FAIL')+'; '+str(len(waits))+' waiting for 822',flush=True)
    return 0 if success else 1
if __name__=='__main__':raise SystemExit(main())
