#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
"""Compose the upstream, fork patch, declared components and native lc1 source."""
import argparse
import io
import json
import lzma
from pathlib import Path
import shutil
import subprocess
import tarfile

p=argparse.ArgumentParser()
p.add_argument('--source',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--toolkit',type=Path,required=True)
a=p.parse_args()
source=a.source.resolve();out=a.out.resolve();toolkit=a.toolkit.resolve()
recipe=Path(__file__).resolve().parent
version='2026.11.12';prefix='spirula-studio-'+version
base='b8e15cb8';out.mkdir(parents=True,exist_ok=True)
head=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
if subprocess.check_output(['git','-C',str(source),'status','--porcelain'],text=True):
    raise SystemExit('Commit the authored source before composing the package')
root=out/prefix
if root.exists():raise SystemExit('Refusing an existing source tree: '+str(root))
def archive_git(repository,revision,destination,arc_prefix):
    data=subprocess.check_output(['git','-C',str(repository),'archive','--format=tar','--prefix='+arc_prefix,revision])
    with lzma.open(destination,'wb',preset=6) as f:f.write(data)
    return data
main=archive_git(source,base,out/f'spirula-studio_{version}.orig.tar.xz',prefix+'/')
with tarfile.open(fileobj=io.BytesIO(main)) as tar:tar.extractall(out,filter='data')
shutil.copytree(recipe/'debian',root/'debian')
patches=root/'debian/patches';patches.mkdir()
patch=subprocess.check_output(['git','-C',str(source),'diff','--binary',base,head])
(patches/'edition.patch').write_bytes(('From: Daniel Campos Ramos\nOrigin: other, https://github.com/Sparky-OS/spirula-studio/commit/'+head+'\nDescription: Edition stereo, depth, installed profiles and Graphics GPU integration\nForwarded: not-needed\n\n').encode()+patch)
(patches/'series').write_text('edition.patch\n')
components={}
for component in ['glfw','imgui']:
    tree=source/'build_vulkan/_deps'/f'{component}-src'
    revision=subprocess.check_output(['git','-C',str(tree),'rev-parse','HEAD'],text=True).strip()
    data=archive_git(tree,revision,out/f'spirula-studio_{version}.orig-{component}.tar.xz',component+'/')
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:tar.extractall(root,filter='data')
    components[component]=revision
fonts=source/'build_vulkan/fonts'
with tarfile.open(out/f'spirula-studio_{version}.orig-fonts.tar.xz','w:xz') as tar:
    for path in sorted(fonts.glob('*.otf')):
        info=tar.gettarinfo(str(path),arcname='fonts/'+path.name);info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0
        with path.open('rb') as f:tar.addfile(info,f)
shutil.copytree(fonts,root/'fonts')
(root/'debian/source/options').write_text('extend-diff-ignore = "^(build_vulkan|build_cuda|slang|\\.sparky-lc)/"\n')
subprocess.run(['dpkg-source','--before-build',str(root)],check=True)
# The Slang headers and marker-bearing code-generation inputs have extra readers.
preserve=[('src/shaders/*','Shared Slang/CUDA shader input; GCC-only token qualification does not qualify the shader reader'),
          ('src/backend/api/*','Generated interface text retains the header-generator marker'),
          ('src/engine/EngineColorSpace.cpp','Read by the upstream auto-header generator'),
          ('src/backend/vulkan/kernels/Visualizer.cpp','Read by the upstream auto-header generator')]
command=['python3','-m','lean.debian_prepare',str(root),'2026.11.12-1+stereo3d1+lc1','--toolkit',str(toolkit)]
for pattern,reason in preserve:command+=['--preserve-source',pattern,reason]
env=__import__('os').environ.copy();env['PYTHONPATH']=str(toolkit);env['DEBFULLNAME']='Daniel Ramos (Capitain Jack)';env['DEBEMAIL']='Capitain_Jack@yahoo.com'
subprocess.run(command,env=env,check=True)
smoke=root/'debian/sparky-lean-toolkit/lean/smoke.tsv'
with smoke.open('a') as f:
    f.write('spirula-studio\t/usr/lib/spirula-studio/vulkan/spirula\t--version\nspirula-studio-cuda\t/usr/lib/spirula-studio/cuda/spirula\t--version\n')
(root/'debian/build-origin.json').write_text(json.dumps(dict(upstream=base,fork=head,components=components),indent=2)+'\n')
print(root)
