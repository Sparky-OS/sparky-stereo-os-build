#!/usr/bin/env python3
"""Install exactly the measured compiler's core packages in a throwaway image."""
import json
import os
if os.environ.get("RL541_FIXTURE"):
    from fixture import install
    install()
    raise SystemExit(0)
from pathlib import Path
import subprocess

packages=[]
for p in sorted(Path('/packages').glob('*.deb')):
    name=subprocess.check_output(['dpkg-deb','-f',str(p),'Package'],text=True).strip()
    if name in ('rustc','cargo','libstd-rust-1.99','libstd-rust-dev') or (name.startswith('libstd-rust-') and len(name)==28):
        packages.append(p)
if len(packages)!=5:raise RuntimeError(f'expected five runtime/compiler packages, got {packages}')
subprocess.run(['dpkg','--auto-deconfigure','-i',*map(str,packages)],check=True)
version=subprocess.check_output(['rustc','--version'],text=True)
if not version.startswith('rustc 1.99.1 '):raise RuntimeError('installed compiler is not the named 1.99.1: '+version)
Path('/installed.json').write_text(json.dumps({'archives':[p.name for p in packages],'version':version,'verbose_version':subprocess.check_output(['rustc','-vV'],text=True),'installed_versions':subprocess.check_output(['dpkg-query','-W','rustc','cargo','libstd-rust-1.99','libstd-rust-dev'],text=True)})+'\n')
