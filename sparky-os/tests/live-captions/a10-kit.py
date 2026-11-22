#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""A10 only. Run as root: a10-kit.py STAGE NEW_OUTPUT.
Installs only new packages (refuses upgrades/removals), runs tiny/base on CPU and
both enumerated Radeon devices using private PipeWire, then purges its additions
and removes its downloads. Metrics/logs remain in NEW_OUTPUT. Never run here.
"""
import argparse,ast,hashlib,json,os,re,shlex,shutil,subprocess,sys,time,urllib.request,signal
from pathlib import Path
class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        if not newurl.startswith('https://'):raise ValueError('Non-HTTPS redirect refused')
        return super().redirect_request(req,fp,code,msg,headers,newurl)
HTTP=urllib.request.build_opener(HTTPSRedirect())

MODELS = [{'name': 'ggml-tiny.bin', 'source': 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin', 'bytes': 77691713, 'sha256': 'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21'}, {'name': 'ggml-base.bin', 'source': 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin', 'bytes': 147951465, 'sha256': '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe'}]
CPP = '// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos\n// SPDX-License-Identifier: GPL-3.0-or-later\n// Compile here, but run only from the A10 kit with the explicit recognition guard.\n#include <captiond/client.hpp>\n#include <captiond/testing/pipewire.hpp>\n#include <chrono>\n#include <filesystem>\n#include <fstream>\n#include <sstream>\n#include <thread>\n#include <cstdlib>\n#include <algorithm>\nusing namespace std::chrono_literals;\nusing Clock=std::chrono::steady_clock;\nstatic double seconds(Clock::time_point t) { return std::chrono::duration<double>(t.time_since_epoch()).count(); }\nstatic double ticks(pid_t pid) {\n    std::ifstream f("/proc/"+std::to_string(pid)+"/stat");std::string s;std::getline(f,s);\n    const auto end=s.rfind(\')\');if(end==std::string::npos)return -1;\n    std::istringstream stream(s.substr(end+2));std::vector<std::string> fields;std::string v;\n    while(stream>>v)fields.push_back(v);\n    return fields.size()>12?std::stod(fields[11])+std::stod(fields[12]):-1;\n}\nint main(int argc,char **argv) {\n    const char *guard=std::getenv("LC73_A10_RECOGNITION");\n    std::ifstream cpu("/proc/cpuinfo");std::string info((std::istreambuf_iterator<char>(cpu)),{});\n    if(argc!=6 || !guard || std::string(guard)!="I_choose_model_runs_on_A10" || info.find("A10-9600P")==std::string::npos)return 2;\n    const std::string model=argv[1],device=argv[2],expected=argv[3],wav=argv[4];\n    const std::filesystem::path out=argv[5];std::filesystem::create_directories(out/"runtime");\n    std::filesystem::permissions(out/"runtime",std::filesystem::perms::owner_all);\n    captiond::testing::PrivatePipeWire pw;if(!pw.up())return 3;\n    std::ofstream(out/"captiond.conf") << "";\n    const std::string sock=(out/"runtime/captiond.sock").string();\n    auto env=captiond::testing::merged(pw.linkable_environment(),{{"CAPTIOND_SINGLE_INSTANCE","false"},{"CAPTIOND_GPU_DEVICE",device=="cpu"?"0":device},{"CAPTIOND_MODEL_PATH",(out/"no-models").string()},{"XDG_DATA_HOME",(out/"data").string()},{"XDG_DATA_DIRS",(out/"no-models").string()},{"XDG_CONFIG_HOME",(out/"config").string()},{"DBUS_SESSION_BUS_ADDRESS",std::nullopt}});\n    std::vector<std::string> args={"--config",(out/"captiond.conf").string(),"--socket",sock,"--engine","whisper","--model",model,"--language","en","--source","sink:captiond-test-sink","--log-level","debug"};\n    if(device=="cpu")args.push_back("--no-gpu");\n    const int logfd=::open((out/"daemon.log").c_str(),O_WRONLY|O_CREAT|O_TRUNC,0600);\n    captiond::testing::Process daemon("/usr/bin/captiond",args,env,logfd);::close(logfd);\n    captiond::Client client;captiond::Status status;\n    std::ofstream events(out/"events.jsonl"),loads(out/"load.jsonl");\n    std::vector<std::pair<double,captiond::Caption>> captions;\n    client.on_status([&](const captiond::Status &s){status=s;events<<nlohmann::json{{"received_monotonic_s",seconds(Clock::now())},{"event",captiond::status_event(s)}}.dump()<<std::endl;});\n    client.on_caption([&](const captiond::Caption &c){captions.emplace_back(seconds(Clock::now()),c);events<<nlohmann::json{{"received_monotonic_s",captions.back().first},{"event",captiond::caption_event(c)}}.dump()<<std::endl;});\n    client.on_error([&](const captiond::Error &e){events<<nlohmann::json{{"error",e.message}}.dump()<<std::endl;});\n    const auto load_start=Clock::now();bool connected=false;\n    while(Clock::now()-load_start<180s && daemon.running()) {\n        if(!connected)connected=client.connect(sock);\n        if(connected){client.process();if(status.state==captiond::DaemonState::Listening)break;}\n        std::this_thread::sleep_for(20ms);\n    }\n    nlohmann::json result={{"device_requested",device},{"expected_accelerator",expected},{"status",captiond::status_event(status)},{"load_seconds",seconds(Clock::now())-seconds(load_start)}};\n    if(status.state!=captiond::DaemonState::Listening || (device=="cpu"?status.gpu:(!status.gpu || status.accelerator.find(expected)==std::string::npos))) {\n        result["error"]="Requested recognizer/device did not become ready; no silent CPU or other-card fallback accepted";\n        std::ofstream(out/"result.json")<<result.dump(2);return 4;\n    }\n    if(!pw.link_output())return 5;\n    nlohmann::json trials=nlohmann::json::array();bool all=true;\n    for(int trial=0;trial<1;++trial) {\n        const auto start=Clock::now();const double cpu_start=ticks(daemon.pid());const std::size_t first=captions.size();\n        auto player=pw.play_through_the_speakers(wav);if(!player.started())return 6;\n        double end=0,final=0;std::string text;bool behind=false;\n        auto next_sample=start;\n        while(Clock::now()-start<90s && daemon.running()) {\n            client.process();behind=behind||status.behind;\n            const auto now=Clock::now();\n            if(!end && !player.running())end=seconds(now);\n            for(std::size_t n=first;n<captions.size();++n) {\n                const auto &c=captions[n].second;std::string lower=c.committed;\n                std::transform(lower.begin(),lower.end(),lower.begin(),[](unsigned char x){return std::tolower(x);});\n                if(c.final && lower.find("quick brown fox")!=std::string::npos && lower.find("lazy dog")!=std::string::npos) {final=captions[n].first;text=c.committed;break;}\n            }\n            if(now>=next_sample) {std::ifstream f("/proc/loadavg");std::string l;std::getline(f,l);loads<<nlohmann::json{{"monotonic_s",seconds(now)},{"loadavg",l},{"daemon_cpu_ticks",ticks(daemon.pid())}}.dump()<<std::endl;next_sample=now+100ms;}\n            if(end && final)break;\n            std::this_thread::sleep_for(10ms);\n        }\n        const double elapsed=seconds(Clock::now())-seconds(start),used=ticks(daemon.pid())-cpu_start;\n        nlohmann::json row={{"trial",trial+1},{"playback_start_monotonic_s",seconds(start)},{"playback_drain_monotonic_s",end},{"final_caption_monotonic_s",final},{"text",text},{"behind_seen",behind},{"daemon_cpu_percent_one_core",100*used/::sysconf(_SC_CLK_TCK)/elapsed},{"passed",end>0&&final>0}};\n        if(end && final)row["final_delay_after_wav_end_s"]=final-end;else all=false;\n        trials.push_back(row);\n        for(int n=0;n<300;++n){client.process();std::this_thread::sleep_for(10ms);}\n    }\n    result["trials"]=trials;result["metric"]="Final recognized fox phrase arrival minus pw-cat playback drain (end of WAV), sampled at 10 ms; includes live caption settlement, excludes model load. Private null-sink playback, not a physical speaker timing measurement.";\n    std::ofstream(out/"result.json")<<result.dump(2)<<\'\\n\';client.close();daemon.terminate();return all?0:7;\n}\n'

def command(args,**kwargs):
    return subprocess.run(args,text=True,check=True,**kwargs)

def installed():
    rows=subprocess.check_output(['dpkg-query','-W','-f=${binary:Package}\t${Version}\t${db:Status-Status}\n'],text=True)
    return {p:v for p,v,s in (line.split('\t') for line in rows.splitlines()) if s=='installed'}

def package_plan(text):
    return [line.split()[1] for line in text.splitlines() if line.startswith('Inst ')]

def run_probe(args,env):
    proc=subprocess.Popen(args,env=env,start_new_session=True)
    try:
        return proc.wait(timeout=600)
    finally:
        if proc.poll() is None:
            def descendants(pid):
                try:children=[int(x) for x in Path(f'/proc/{pid}/task/{pid}/children').read_text().split()]
                except FileNotFoundError:return []
                result=[]
                for child in children:result.extend(descendants(child));result.append(child)
                return result
            owned=descendants(proc.pid)+[proc.pid]
            for pid in owned:
                try:os.kill(pid,signal.SIGTERM)
                except ProcessLookupError:pass
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                for pid in owned:
                    try:os.kill(pid,signal.SIGKILL)
                    except ProcessLookupError:pass
                proc.wait()

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('stage',type=Path);parser.add_argument('output',type=Path);args=parser.parse_args()
    if 'A10-9600P' not in Path('/proc/cpuinfo').read_text():raise SystemExit('Refused: this kit runs recognition only on the A10-9600P bench.')
    if os.geteuid()!=0:raise SystemExit('Run this reviewed kit with sudo; package cleanup needs root.')
    stage=args.stage.resolve(strict=True);out=args.output.resolve()
    if out.exists():raise SystemExit('Output must be a new folder.')
    out.mkdir(parents=True);work=out/'scratch';work.mkdir();cache=work/'apt-cache';cache.mkdir()
    before=installed();(out/'packages-before.json').write_text(json.dumps(before,indent=2))
    expected={line.split(None,1)[1].lstrip('* '):line.split()[0] for line in (stage/'SHA256SUMS').read_text().splitlines()}
    names=['captiond','libcaptiond-client0','libcaptiond-client-dev','libcaptiond-client-tests-dev','kaption','qaption','kaption-common']
    debs=[]
    for name in names:
        files=list(stage.glob(name+'_0.1.0-1+lc1_*.deb'))
        if len(files)!=1:raise SystemExit('Need exactly one staged '+name+' package')
        p=files[0];assert hashlib.sha256(p.read_bytes()).hexdigest()==expected[p.name];debs.append(str(p))
    wanted=debs+['g++','pkgconf','pipewire-bin','libwhisper1=1.9.5+dfsg-1','libggml0=0.29.0-1']
    apt=['apt-get','-y','--no-install-recommends','-o','Dir::Cache::archives='+str(cache)]
    env=dict(os.environ,DEBIAN_FRONTEND='noninteractive');new=[];success=False;cleanup_error=None
    try:
        plan=subprocess.check_output(apt+['--simulate','install']+wanted,text=True,env=env);(out/'install-plan.txt').write_text(plan)
        if any(line.startswith('Remv ') for line in plan.splitlines()):raise RuntimeError('Install would remove an existing package; refused.')
        planned=package_plan(plan)
        def already(p):return p in before or p+':amd64' in before
        if any(already(p) for p in planned):raise RuntimeError('Install would change an existing package version; refused.')
        new=planned
        uris=subprocess.check_output(apt+['--print-uris','install']+wanted,text=True,env=env);(out/'download-plan.txt').write_text(uris)
        for line in uris.splitlines():
            if not line.startswith("'"):continue
            uri,filename,size,*digest=shlex.split(line)
            if not uri.startswith(('https://','file:')):raise RuntimeError('Non-HTTPS package download refused: '+uri)
            print('Package input:',uri,size,'bytes',flush=True)
        command(apt+['--download-only','install']+wanted,env=env,stdout=(out/'apt-download.log').open('w'),stderr=subprocess.STDOUT)
        archive_manifest=[dict(file=p.name,bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in cache.glob('*.deb')]
        (out/'package-download-checksums.json').write_text(json.dumps(archive_manifest,indent=2))
        recheck=subprocess.check_output(apt+['--simulate','install']+wanted,text=True,env=env)
        if package_plan(recheck)!=planned:raise RuntimeError('Package plan changed during download; refused.')
        command(['unshare','--net']+apt+['install']+wanted,env=env,stdout=(out/'apt-install.log').open('w'),stderr=subprocess.STDOUT)
        after=installed();(out/'packages-during.json').write_text(json.dumps(after,indent=2))
        for package,version in [('libwhisper1','1.9.5+dfsg-1'),('libggml0','0.29.0-1')]:
            if after.get(package,after.get(package+':amd64'))!=version:raise RuntimeError('Wrong backend version: '+package)
        devices=subprocess.check_output(['captiond','--list-devices'],text=True);(out/'devices.txt').write_text(devices)
        cards=[]
        for line in devices.splitlines():
            match=re.match(r'^(\d+)\s+(\S+)\s+GPU\s+(.+)$',line)
            if match and re.search('AMD|Radeon',match[3],re.I):cards.append((match[1],match[3]))
        if len(cards)!=2:raise RuntimeError('Expected two enumerated Radeon GPU devices; found '+repr(cards)+'. Nothing is silently routed to another device.')
        source=work/'probe.cpp';source.write_text(CPP);binary=work/'probe'
        command(['g++','-std=c++20','-O2',str(source),'-o',str(binary),'-lcaptiond-client','-pthread'],stdout=(out/'compile.log').open('w'),stderr=subprocess.STDOUT)
        modeldir=work/'models';modeldir.mkdir()
        for m in MODELS:print('Model download:',m['name'],m['source'],m['bytes'],'bytes SHA256',m['sha256'],flush=True)
        for m in MODELS:
            dest=modeldir/m['name'];h=hashlib.sha256();size=0
            request=urllib.request.Request(m['source'],headers={'Accept-Encoding':'identity'})
            with HTTP.open(request,timeout=60) as response,dest.open('wb') as f:
                if not response.url.startswith('https://'):raise RuntimeError('Non-HTTPS model redirect refused')
                while chunk:=response.read(1024*1024):
                    size+=len(chunk)
                    if size>m['bytes']:raise RuntimeError('Model exceeds declared size')
                    h.update(chunk);f.write(chunk)
            if size!=m['bytes'] or h.hexdigest()!=m['sha256']:raise RuntimeError('Model checksum/size mismatch: '+m['name'])
        (out/'model-downloads.json').write_text(json.dumps(MODELS,indent=2))
        runenv=dict(os.environ,LC73_A10_RECOGNITION='I_choose_model_runs_on_A10')
        rows=[]
        for m in MODELS:
            for device,description in [('cpu','CPU')]+cards:
                for trial in range(1,4):
                    resultdir=out/(m['name'].removesuffix('.bin')+'-'+device+'-trial'+str(trial))
                    rc=run_probe([str(binary),str(modeldir/m['name']),device,description,'/usr/share/captiond/testing/fox.wav',str(resultdir)],runenv)
                    rows.append(dict(model=m['name'],device=device,description=description,trial=trial,exit=rc,result=str(resultdir/'result.json')))
        (out/'rows.json').write_text(json.dumps(rows,indent=2));success=all(r['exit']==0 for r in rows)
    finally:
        try:
            now=installed();remove=[p for p in new if p in now or p+':amd64' in now]
            if remove:
                plan=subprocess.check_output(['apt-get','--simulate','purge']+remove,text=True,env=env)
                removals={line.split()[1].split(':')[0] for line in plan.splitlines() if line.startswith(('Remv ','Purg '))}
                allowed={p.split(':')[0] for p in remove}
                if not removals<=allowed:raise RuntimeError('Cleanup would remove another package; refused: '+repr(removals-allowed))
                command(['apt-get','-y','purge']+remove,env=env,stdout=(out/'apt-remove.log').open('w'),stderr=subprocess.STDOUT)
            remaining=installed();(out/'packages-after.json').write_text(json.dumps(remaining,indent=2))
            changed={p:(v,remaining.get(p)) for p,v in before.items() if remaining.get(p)!=v}
            leftover={p:v for p,v in remaining.items() if p not in before and p.split(':')[0] in {x.split(':')[0] for x in new}}
            if changed or leftover:raise RuntimeError('Cleanup differs: '+repr(dict(changed=changed,leftover=leftover)))
        except Exception as e:cleanup_error=str(e)
        shutil.rmtree(work)
        (out/'cleanup.json').write_text(json.dumps(dict(scratch_removed=not work.exists(),package_cleanup_error=cleanup_error),indent=2))
    print('row\texpected\tfound')
    for row in rows:print(row['model']+'/'+row['device']+'\trecognition on requested device\texit '+str(row['exit']))
    print('cleanup\toriginal package versions, no kit downloads\t'+(cleanup_error or 'restored'))
    return 0 if success and cleanup_error is None else 1
if __name__=='__main__':raise SystemExit(main())
