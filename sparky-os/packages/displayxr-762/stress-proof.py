#!/usr/bin/env python3
"""Reproduce first-attachment loss, then run the unchanged patched CTest 200 times under load."""
import json,os,pathlib,re,shlex,subprocess,sys
source=pathlib.Path(sys.argv[1]).resolve();build=source/'obj-x86_64-linux-gnu';out=pathlib.Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
path=source/'tests/tests_viewer_pose_page.cpp';green=path.read_text()
a=green.index('TEST_CASE("viewer pose page: torn-read stress');b=green.index('\n#if',a)
case=green[a:b]
decl='\tu_vpp_reader r = {};\n\tstd::vector<xrt_tracking_viewer_sample> out(U_VPP_RING_SIZE);\n'
attach=decl+'\t(void)u_vpp_read_new(p.mem, &r, out.data(), U_VPP_RING_SIZE);\n\n'
assert case.count(attach)==1
# Diagnostic only: restore the original first attachment, then wait for the writer
# to finish before that first read. No assertion or product implementation changes.
redcase=case.replace(attach,'').replace('\twriter.join();\n','').replace('\tfor (;;) {','\twriter.join();\n'+decl+'\tfor (;;) {',1)
red=green[:a]+redcase+green[b:]
assert [l for l in red.splitlines() if 'CHECK('in l or 'REQUIRE('in l]==[l for l in green.splitlines() if 'CHECK('in l or 'REQUIRE('in l]
redpath=out/'red.cpp';redpath.write_text(red)
commands=subprocess.check_output(['ninja','-t','commands','tests_viewer_pose_page'],cwd=build,text=True).splitlines()
compilecmd=next(c for c in commands if ' -c 'in c and c.endswith('/tests/tests_viewer_pose_page.cpp'))
args=shlex.split(compilecmd);obj=args[args.index('-o')+1];redobj=str(out/'red.o')
args[args.index('-o')+1]=redobj;args[args.index('-c')+1]=str(redpath)
if '-MF'in args:args[args.index('-MF')+1]=str(out/'red.o.d')
subprocess.run(args,cwd=build,check=True)
link=next(c for c in reversed(commands) if obj in c and ' -o tests/tests_viewer_pose_page 'in c and ' -c 'not in c)
# Ninja emits a shell wrapper for this link command; it is copied verbatim with
# only the object and output paths changed, all from known local build paths.
link=link.replace(obj,shlex.quote(redobj)).replace('-o tests/tests_viewer_pose_page ','-o '+shlex.quote(str(out/'red'))+' ')
subprocess.run(['bash','-c',link],cwd=build,check=True)
with (out/'red.log').open('w') as log:r=subprocess.run([str(out/'red'),'[vpp][stress]','--reporter','compact'],cwd=build,stdout=log,stderr=subprocess.STDOUT)
text=(out/'red.log').read_text()
if r.returncode!=1 or '200000'not in text:raise SystemExit('The deterministic red did not show the expected assertion')
# Four bounded CPU load processes share the container's four-CPU quota.
workers=[subprocess.Popen([sys.executable,'-c','import time\nend=time.monotonic()+1800\nx=0\nwhile time.monotonic()<end: x=(x+1)%104729']) for _ in range(4)]
try:
 with (out/'green-200.log').open('w') as log:
  r=subprocess.run(['ctest','--test-dir',str(build),'-R','^tests_viewer_pose_page$','--repeat','until-fail:200','--output-on-failure','--timeout','300','-j1'],stdout=log,stderr=subprocess.STDOUT)
finally:
 for w in workers:w.terminate()
 for w in workers:w.wait()
greenlog=(out/'green-200.log').read_text();passes=len(re.findall(r'Test\s+#\d+: tests_viewer_pose_page\s+\.+'+r'\s+Passed',greenlog))
result={'red_exit':1,'green_exit':r.returncode,'green_passes':passes,'load_workers':4,'assertions_unchanged':True}
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if r.returncode or passes!=200:raise SystemExit(1)
