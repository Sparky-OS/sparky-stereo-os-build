#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Add the multiview consumer delta to the edition's native source packages."""
import argparse,os,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('project',choices=['mpv','qt','vlc','gwenview']);p.add_argument('source',type=Path);p.add_argument('version')
a=p.parse_args();source=a.source.resolve();recipe=Path(__file__).resolve().parent
if 'lean.source_tree project' not in (source/'debian/rules').read_text():
 raise ValueError('Use the recorded published native Lean Code baseline')
name=a.project+'-mvhevc.patch';target=source/'debian/patches'/name
if target.exists():raise ValueError('Refusing to replace an existing patch')
shutil.copy2(recipe/'patches'/name,target)
with (source/'debian/patches/series').open('a') as stream:stream.write(name+'\n')
env=os.environ|{'DEBFULLNAME':'Daniel Ramos (Capitain Jack)','DEBEMAIL':'Capitain_Jack@yahoo.com','QUILT_PATCHES':'debian/patches'}
subprocess.run(['quilt','push'],cwd=source,env=env,check=True)
if a.project == 'vlc':
 translation='vlc-spatial-video-translations.patch'
 shutil.copy2(recipe.parents[1]/'translations/vlc-spatial-video.po.patch', source/'debian/patches'/translation)
 with (source/'debian/patches/series').open('a') as stream:stream.write(translation+'\n')
 subprocess.run(['quilt','push'],cwd=source,env=env,check=True)
control=source/'debian/control';text=control.read_text().replace('Build-Depends:','Build-Depends: libstereo-av-dev (>= 1.12.0-1+lc1),',1)
if a.project == 'gwenview':
 text=text.replace('Build-Depends:', 'Build-Depends: qt6-multimedia-private-dev (>= 6.11.2-3+stereo3d10+lc1),',1)
 text=text.replace('qt6-multimedia-dev', 'qt6-multimedia-dev (>= 6.11.2-3+stereo3d10+lc1)')
 text=text.replace('Depends: ${shlibs:Depends}', 'Depends: libqt6multimedia6 (>= 6.11.2-3+stereo3d10+lc1), ${shlibs:Depends}',1)
control.write_text(text)
subprocess.run(['dch','--newversion',a.version,'--distribution','UNRELEASED','Decode and assemble both signalled MV-HEVC views without resizing, retaining presentation metadata, base-view fallback and per-file correction.'],cwd=source,env=env,check=True)
