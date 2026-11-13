#!/usr/bin/env python3
"""Assemble a tiny fixture kit with the production runner and collectors."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from seal import seal
from make_plan import plan


def fixture(output, scripts, toolkit, subject, image):
    output.mkdir()
    shutil.copytree(scripts,output/'scripts',ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copytree(toolkit/'lean',output/'scripts/lean',ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copytree(subject,output/'subject')
    for n in ('run.sh','status.sh','pause.sh'):shutil.copy2(scripts/n,output/n)
    source=output/'fixture-source';source.mkdir()
    code='''fn main() {
    let s = std::process::Command::new("/usr/bin/rustc").args(std::env::args_os().skip(1)).status().unwrap();
    std::process::exit(s.code().unwrap_or(127));
}
'''
    (source/'main.rs').write_text('// authored fixture\n'+code)
    p=source/'library/std/src/io';p.mkdir(parents=True)
    (p/'stdio.rs').write_text('#![allow(dead_code)]\npub fn fail() { panic!("failed printing to stdout: fixture"); }\n')
    crate=source/'library/vendor/fixture-source-0.1.0';(crate/'src').mkdir(parents=True)
    (crate/'Cargo.toml').write_text('[package]\nname="fixture-source"\nversion="0.1.0"\nedition="2024"\n')
    forms={}
    for f in 'ABC':
        # B/C have removed source commentary, while the real compiled forwarding code is unchanged.
        (source/'main.rs').write_text(('// authored fixture\n' if f=='A' else '')+code)
        (crate/'src/lib.rs').write_text(('// ordinary fixture commentary\n' if f=='A' else '')+('/// Documentation for the source fixture.\n' if f!='C' else '')+'pub fn value() -> u32 { 7 }\n')
        checksum={'files':{n:hashlib.sha256((crate/n).read_bytes()).hexdigest() for n in ('Cargo.toml','src/lib.rs')},'package':None}
        (crate/'.cargo-checksum.json').write_text(json.dumps(checksum,sort_keys=True)+'\n')
        forms[f]=seal(source,output/'sources',f,1794523022)['tree_sha256']
    shutil.rmtree(source)
    data=plan(image,forms,fixture=True)
    data['engine']=['docker']
    # Two startup blocks and one each of the larger tasks exercise every path.
    data['steps']=[s for s in data['steps'] if s['kind']!='runtime' or int(s['id'].split('-')[1])==0]
    (output/'plan.json').write_text(json.dumps(data,indent=2)+'\n')
    sums=[]
    for p in sorted(output.rglob('*')):
        if p.is_file():sums.append(hashlib.file_digest(p.open('rb'),'sha256').hexdigest()+'  '+p.relative_to(output).as_posix())
    (output/'SHA256SUMS').write_text('\n'.join(sums)+'\n')


if __name__=='__main__':
    p=argparse.ArgumentParser()
    for n in ('output','scripts','toolkit','subject'):p.add_argument(n,type=Path)
    p.add_argument('image');a=p.parse_args();fixture(**vars(a))
