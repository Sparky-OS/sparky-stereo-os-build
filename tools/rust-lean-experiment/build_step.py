#!/usr/bin/env python3
"""One offline whole toolchain or repeated compiler-check step, inside the image."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from measure import run
from inputs import census


def command(argv): subprocess.run(argv,check=True)


def bind_hash(tree):
    # Discovery is the edition recipe's content hash, never a guessed constant.
    libs=list((tree/'build/x86_64-unknown-linux-gnu/stage2/lib/rustlib/x86_64-unknown-linux-gnu/lib').glob('libstd-*.so'))
    if len(libs)!=1: raise RuntimeError('expected exactly one stage2 libstd runtime')
    found=re.fullmatch(r'libstd-([0-9a-f]{16})\.so',libs[0].name).group(1)
    deb=tree/'debian'
    for p in list(deb.iterdir()):
        if p.is_file() and not p.is_symlink() and (p.name in ('control','sparky-libstd-hash') or p.name.startswith('libstd-rust-discover.')):
            data=p.read_bytes()
            if b'discover' in data:
                # Only recipe metadata contains the placeholder; no tool/source transforms.
                if p.suffix in ('.py','.sh') or p.name in ('sparky-libstd-runtime',): continue
                p.write_bytes(data.replace(b'discover',found.encode()))
            if 'discover' in p.name: p.rename(p.with_name(p.name.replace('discover',found)))
    changelog=deb/'changelog';text=changelog.read_text()
    if text.count('libstd-rust-discover')!=2 or text.count('libstd-discover.so')!=1:
        raise RuntimeError('edition changelog no longer has the three reviewed discovery placeholders')
    changelog.write_text(text.replace('libstd-rust-discover','libstd-rust-'+found).replace('libstd-discover.so','libstd-'+found+'.so'))
    (deb/'sparky-libstd-hash').write_text(found+'\n')
    return found


def main(kind,cpus):
    if os.environ.get('RL541_FIXTURE'):
        from fixture import build
        return build(kind,cpus)
    tree=Path('/work/tree'); out=Path('/work/result');out.mkdir()
    os.chdir(tree)
    seed=subprocess.check_output(['dpkg-query','-W','-f=${Version}','rustc'],text=True)
    if seed!='1.98.1+dfsg1-1+stereo3d1+lc1':raise RuntimeError('seed compiler version mismatch: '+seed)
    os.environ.update(LC_ALL='C',CARGO_NET_OFFLINE='true',DEB_BUILD_OPTIONS=f'parallel={cpus} nocheck',
                      SOURCE_DATE_EPOCH='1794523022',DEBFULLNAME='Daniel Ramos (Capitain Jack)',
                      DEBEMAIL='Capitain_Jack@yahoo.com',RL541_AUTHORED='/authored',RL541_FORM_SOURCE='/form')
    command(['make','-f','debian/rules','debian/dh_auto_configure.stamp'])
    if kind=='check':
        run(['python3','src/bootstrap/bootstrap.py','check','--stage','1','--config','debian/config.toml',
             '-j'+cpus,'compiler','library'],out/'compile')
    elif kind=='whole':
        run(['make','-f','debian/rules','build'],out/'compile')
        found=bind_hash(tree)
        (out/'std-hash.txt').write_text(found+'\n')
        shutil.copytree(tree/'debian',out/'bound-packaging',ignore=shutil.ignore_patterns('sparky-lean-toolkit','patches'))
        run(['dpkg-buildpackage','-us','-uc','-b','-nc','-j'+cpus],out/'package')
        packages=sorted(Path('/work').glob('*.deb'))
        if not packages: raise RuntimeError('no packages assembled')
        (out/'packages').mkdir()
        for p in packages: shutil.move(p,out/'packages'/p.name)
        shutil.copy2(tree/'debian/rl541-restored-rust.json',out/'rust-src-restored.json')
    else: raise ValueError(kind)
    shutil.copy2(tree/'debian/config.toml',out/'config.toml')
    (out/'environment.json').write_text(json.dumps({k:os.environ[k] for k in ('LC_ALL','CARGO_NET_OFFLINE','DEB_BUILD_OPTIONS','SOURCE_DATE_EPOCH')},indent=2)+'\n')
    census(tree,out/'inputs.json',Path('/form'))
    (out/'step.json').write_text(json.dumps({'kind':kind,'complete':True,'seed':seed})+'\n')


if __name__=='__main__': main(*sys.argv[1:])
