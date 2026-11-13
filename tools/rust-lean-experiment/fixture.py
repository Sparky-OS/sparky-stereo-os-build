#!/usr/bin/env python3
"""Explicit small-scale runner subjects; none of their numbers are experiment results."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from measure import run
from inputs import census
from package_wrapper import restore


def build(kind,cpus):
    tree=Path('/work/tree');out=Path('/work/result');out.mkdir();os.chdir(tree)
    # The forwarding compiler is a real ELF, compiled separately from each form.
    argv=['/usr/bin/rustc','--edition=2024','--emit=dep-info,link' if kind in ('whole','stage1') else '--emit=dep-info,metadata',
          '-C','debuginfo=2','-C','link-arg=-Wl,--compress-debug-sections=zlib','--remap-path-prefix=/work=/experiment','main.rs','-o','/work/fixture-rustc']
    run(argv,out/'compile')
    # Put real compiler dep-info under build/, as in bootstrap.
    (tree/'build').mkdir();shutil.copy2('/work/fixture-rustc.d',tree/'build/fixture.d')
    if kind=='whole':
        from lean.release import build_tree
        stage=Path('/work/staging');(stage/'DEBIAN').mkdir(parents=True)
        (stage/'DEBIAN/control').write_text('Package: rl541-fixture-compiler\nVersion: 1.0+lc1\nArchitecture: amd64\nMaintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nDescription: Small runner fixture\n')
        dest=stage/'usr/local/bin';dest.mkdir(parents=True);shutil.copy2('/work/fixture-rustc',dest/'rustc')
        source=stage/'usr/src/rustc-1.99.1';shutil.copytree(tree,source,ignore=shutil.ignore_patterns('build'))
        restored=restore(source,Path('/authored'),Path('/form'))
        (out/'rust-src-restored.json').write_text(json.dumps(restored)+'\n')
        (out/'packages').mkdir()
        build_tree(stage,out/'packages',preserve={'/usr/src/rustc-*':'authored fixture sources'})
    census(tree,out/'inputs.json',Path('/form'))
    # A deterministic interrupted-step test kills the worker after this marker.
    (out/'fixture-marker').write_text('metrics done, receipt not committed\n')
    if os.environ.get('RL541_FIXTURE_DELAY'):time.sleep(float(os.environ['RL541_FIXTURE_DELAY']))
    (out/'step.json').write_text('{"complete":true,"fixture":true}\n')


def install():
    packages=list(Path('/packages').glob('rl541-fixture-compiler_*.deb'))
    if len(packages)!=1:raise RuntimeError('fixture package missing')
    subprocess.run(['dpkg','-i',str(packages[0])],check=True)
    got=subprocess.check_output(['/usr/local/bin/rustc','--version'],text=True)
    if not got.startswith('rustc 1.98.1 '):raise RuntimeError('fixture forwarded an unexpected compiler')
    Path('/installed.json').write_text(json.dumps({'fixture':True,'version':got,'archives':[p.name for p in packages]})+'\n')


def panic(out):
    root=Path('/work/library/std/src/io');root.mkdir(parents=True)
    # A clearly labelled fixture, exercising the same location extraction and resolver.
    (root/'stdio.rs').write_text('pub fn fail() { panic!("failed printing to stdout: fixture"); }\n')
    Path('/work/panic.rs').write_text('#[path="library/std/src/io/stdio.rs"] mod stdio; fn main(){stdio::fail();}\n')
    run(['rustc','/work/panic.rs','-o','/work/panic'],out/'compile')
    run(['/work/panic'],out/'panic',expected=101)
