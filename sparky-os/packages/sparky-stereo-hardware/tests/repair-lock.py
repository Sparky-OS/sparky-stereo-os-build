#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Root in a disposable Docker container ONLY, Hardware Setup and engine installed.

Real apt/dpkg, real frontend lock held by another apt transaction; no mocked
commands. Empty NVIDIA-named packages test version selection/install state, not
GPU binaries. Usage: repair-lock.py EVIDENCE [VERSION]. Always expects the fixed
behavior; baseline 0.1.21 must fail. Requires dpkg-dev for the local fixture repo.
"""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

assert os.geteuid() == 0 and Path('/.dockerenv').exists(), 'Disposable container only'
evidence = Path(sys.argv[1]); evidence.mkdir(parents=True, exist_ok=True)
version = sys.argv[2] if len(sys.argv) > 2 else '615.71.09-2'
engine = ['sparky-stereo-problems']
record = Path('/var/lib/sparky-stereo-problems/sparky-stereo-hardware_nvidia-i386.json')
failures = []

def check(ok, message):
    print(('PASS ' if ok else 'FAIL ') + message, flush=True)
    if not ok: failures.append(message)

def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def installed(arch):
    p = subprocess.run(['dpkg-query', '-W', '-f', '${db:Status-Abbrev}\t${Version}', arch], capture_output=True, text=True)
    return p.stdout.startswith('ii ') and p.stdout.strip().endswith(version)

with tempfile.TemporaryDirectory(prefix='order368-repair-') as td:
    work = Path(td); work.chmod(0o755)
    repo = work/'repo'; repo.mkdir()
    def deb(name, arch, multi=False):
        tree=work/f'{name}-{arch}'; (tree/'DEBIAN').mkdir(parents=True)
        (tree/'DEBIAN/control').write_text(f'Package: {name}\nVersion: {version}\nArchitecture: {arch}\nMaintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\n'+('Multi-Arch: same\n' if multi else '')+'Description: ORDER 368 empty lock-test fixture, not NVIDIA binaries\n')
        marker=tree/f'usr/share/order368-fixture/{name}-{arch}'
        marker.parent.mkdir(parents=True); marker.write_text(f'{name} {arch} {version}\n')
        target=repo/f'{name}_{version}_{arch}.deb'
        run(['dpkg-deb','--root-owner-group','-b',str(tree),str(target)], stdout=subprocess.DEVNULL)
        return target
    amd64=deb('nvidia-driver-libs','amd64',True)
    deb('nvidia-driver-libs','i386',True); deb('libcuda1','i386',True)
    deb('order368-apt-holder','all')
    with (repo/'Packages').open('w') as out:
        run(['dpkg-scanpackages','-m','.'],cwd=repo,stdout=out)
    (work/'lists/partial').mkdir(parents=True)
    (work/'empty').mkdir()
    (work/'sources.list').write_text(f'deb [trusted=yes] file:{repo} ./\n')
    config=work/'apt.conf'
    config.write_text(f'Dir::Etc::sourcelist "{work}/sources.list";\nDir::Etc::sourceparts "{work}/empty";\nDir::State::lists "{work}/lists";\nAPT::Get::List-Cleanup "false";\n')
    env=dict(os.environ, APT_CONFIG=str(config), DEBIAN_FRONTEND='noninteractive', LC_ALL='C.UTF-8')
    setup_env=dict(env, SPARKY_STEREO_HARDWARE_NVIDIA_I386='installing')
    with (evidence/'setup.log').open('w') as log:
        # This package set belongs entirely to the disposable fixture.
        run(['dpkg','--add-architecture','i386'],env=setup_env,stdout=log,stderr=log)
        for p in ['nvidia-driver-libs:i386','libcuda1:i386','order368-apt-holder']:
            found=subprocess.run(['dpkg-query','-W','-f','${db:Status-Abbrev}',p],capture_output=True,text=True)
            if found.stdout.startswith('ii '):
                run(['dpkg','--purge',p],env=setup_env,stdout=log,stderr=log)
        run(['dpkg','-i',str(amd64)],env=setup_env,stdout=log,stderr=log)
        run(['apt-get','update'],env=env,stdout=log,stderr=log)
        if not record.exists():
            run(engine+['keep','--repair','["sparky-stereo-hardware","--nvidia-i386"]','sparky-stereo-hardware','nvidia-i386','LOCAL5',version,'nvidia-driver-libs:i386, libcuda1:i386'],stdout=log,stderr=log)
    hook=work/'hold.sh'
    hook.write_text(f'#!/bin/sh\ntouch {work}/ready\ni=0\nwhile [ ! -e {work}/release ] && [ "$i" -lt 60 ]; do sleep 1; i=$((i+1)); done\ntest -e {work}/release\n')
    hook.chmod(0o755)
    holder=repair=None
    try:
        with (evidence/'holder.log').open('w') as hl, (evidence/'repair.log').open('w') as rl:
            holder=subprocess.Popen(['apt-get','-y','-o',f'DPkg::Pre-Invoke::={hook}','install','order368-apt-holder'],env=setup_env,stdout=hl,stderr=hl)
            deadline=time.monotonic()+20
            while not (work/'ready').exists() and holder.poll() is None and time.monotonic()<deadline: time.sleep(.1)
            assert (work/'ready').exists() and holder.poll() is None, 'Holder did not reach apt pre-invoke'
            # Independently establish that apt really holds the standard frontend lock.
            with open('/var/lib/dpkg/lock-frontend','a') as fd:
                try:
                    fcntl.lockf(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
                except BlockingIOError:
                    print('PASS real apt holds /var/lib/dpkg/lock-frontend',flush=True)
                else:
                    raise AssertionError('No competing frontend lock')
            repair=subprocess.Popen(['sparky-stereo-hardware','--nvidia-i386'],env=env,stdout=rl,stderr=rl)
            deadline=time.monotonic()+20
            while time.monotonic()<deadline and repair.poll() is None:
                if 'Waiting for cache lock' in (evidence/'repair.log').read_text(): break
                time.sleep(.1)
            time.sleep(2)
            before=(evidence/'repair.log').read_text()
            waiting=repair.poll() is None and 'Waiting for cache lock' in before
            check(waiting,'Repair remains running while apt holds its lock')
            check('this repair waits for it to finish' in before,'translated wait explanation is on the terminal before release')
            check(not installed('nvidia-driver-libs:i386') and not installed('libcuda1:i386'),'nothing installed while the competing lock is held')
            if record.exists(): (evidence/'record-before-release.json').write_bytes(record.read_bytes())
            (evidence/'timing.json').write_text(json.dumps({'holder_pid':holder.pid,'repair_pid':repair.pid,'repair_returncode_before_release':repair.poll(),'wait_observed':waiting,'release_monotonic':time.monotonic()},indent=2)+'\n')
            (work/'release').touch()
            hr=holder.wait(timeout=30); rr=repair.wait(timeout=45)
            (evidence/'holder.exit').write_text(str(hr)+'\n'); (evidence/'repair.exit').write_text(str(rr)+'\n')
            check(hr==0,'competing apt transaction finishes after release')
            check(rr==0,'Repair finishes successfully after release')
            check(installed('nvidia-driver-libs:i386') and installed('libcuda1:i386'),'both i386 fixtures actually installed at the amd64 driver version')
            check(not record.exists(),'successful repair clears the kept problem')
            if record.exists(): (evidence/'record-after.json').write_bytes(record.read_bytes())
            if rr==0:
                with (evidence/'already-installed.log').open('w') as log:
                    p=subprocess.run(['sparky-stereo-hardware','--nvidia-i386'],env=env,stdout=log,stderr=log)
                check(p.returncode==0 and not (evidence/'already-installed.log').read_text(),'already installed: success without another apt transaction or wait notice')
    finally:
        (work/'release').touch()
        for proc in [holder,repair]:
            if proc is not None and proc.poll() is None:
                try: proc.wait(timeout=45)
                except subprocess.TimeoutExpired: proc.kill(); proc.wait()
print(f'failures: {len(failures)}')
sys.exit(bool(failures))
