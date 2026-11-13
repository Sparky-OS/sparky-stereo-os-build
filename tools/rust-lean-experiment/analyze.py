#!/usr/bin/env python3
"""Compare all packaged files, ELF sections, workload bytes and panic locations."""
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
from elftools.elf.elffile import ELFFile
from lean.locate import locate


def digest(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()


def logical(s):return re.sub(r'-[0-9a-f]{16}(?=[./]|$)','-HASH',s)


def classify(name):
    if name in ('.debug_line','.debug_line_str'):return 'line tables and source paths'
    if name.startswith(('.debug_','.zdebug_')):return 'debug records; location/hash contributions not causally separated'
    if name=='.rustc':return 'Rust metadata including crate hashes and documentation'
    if name=='.note.gnu.build-id':return 'derived ELF build identifier'
    if name.startswith(('.rela','.rel.')):return 'relocations'
    if name=='.text':return 'machine code and immediates; residual needs instruction-level attribution'
    if name in ('.rodata','.data.rel.ro','.data'):return 'constants and pointers including panic Location records; residual not fully attributed'
    if name in ('.dynstr','.dynsym','.strtab','.symtab'):return 'symbol and string tables, including crate hashes'
    return 'other; residual unclassified'


def sections(a,b):
    with a.open('rb') as fa,b.open('rb') as fb:
        aa=ELFFile(fa);bb=ELFFile(fb)
        sa={s.name:s for s in aa.iter_sections()};sb={s.name:s for s in bb.iter_sections()}
        rows=[]
        for n in sorted(sa.keys()|sb.keys()):
            x,y=sa.get(n),sb.get(n)
            dx=x.data() if x is not None and x['sh_type']!='SHT_NOBITS' else b''
            dy=y.data() if y is not None and y['sh_type']!='SHT_NOBITS' else b''
            if dx==dy and (x['sh_size'] if x is not None else 0)==(y['sh_size'] if y is not None else 0):continue
            changed=sum(c!=d for c,d in zip(dx,dy))+abs(len(dx)-len(dy))
            rows.append({'section':n,'A_bytes':int(x['sh_size']) if x is not None else 0,
                         'other_bytes':int(y['sh_size']) if y is not None else 0,'different_bytes_at_section_offsets':changed,
                         'class':classify(n)})
        return rows


def package_files(packages,destination):
    rows={}
    for pkg in sorted(packages.glob('*.deb')):
        name=subprocess.check_output(['dpkg-deb','-f',str(pkg),'Package'],text=True).strip()
        stage=destination/name;stage.mkdir(parents=True)
        subprocess.run(['dpkg-deb','-x',str(pkg),str(stage)],check=True)
        for p in sorted(stage.rglob('*')):
            if not(p.is_file() or p.is_symlink()):continue
            rel=p.relative_to(stage).as_posix();key=logical(name+'/'+rel)
            if key in rows:raise RuntimeError('logical path collision: '+key)
            rows[key]={'package':name,'path':rel,'file':str(p),'mode':p.lstat().st_mode&0o7777,
                       'bytes':p.lstat().st_size,'link':str(p.readlink()) if p.is_symlink() else None,
                       'sha256':None if p.is_symlink() else digest(p)}
    if not rows:raise RuntimeError('no package files')
    return rows


def source(form,name):
    with tarfile.open('/sources/'+form+'.tar.gz') as tf:
        f=tf.extractfile('./'+name)
        if f is None:raise RuntimeError('panic source absent: '+name)
        return f.read()


def main():
    results=Path('/results');out=Path('/work/result');out.mkdir()
    builds={};panics={}
    for receipt in sorted(results.glob('*/receipt.json')):
        r=json.loads(receipt.read_text());s=r['step'];form=s.get('form')
        if s['kind']=='whole':builds[form]=receipt.parent/'result/packages'
        if s['kind']=='runtime' and s['task']=='panic':panics[form]=receipt.parent/'result/panic/stderr'
    if set(builds)!=set('ABC') or set(panics)!=set('ABC'):raise RuntimeError('missing whole build or panic result')
    inventories={f:package_files(p,Path('/work/unpacked')/f) for f,p in builds.items()}
    clean=lambda r:{k:v for k,v in r.items() if k!='file'}
    (out/'installed-files.json').write_text(json.dumps({f:{n:clean(r) for n,r in rows.items()} for f,rows in inventories.items()},indent=2)+'\n')
    differences=[]
    for f in 'BC':
        a,b=inventories['A'],inventories[f]
        for n in sorted(a.keys()|b.keys()):
            x,y=a.get(n),b.get(n)
            if x is not None and y is not None and {k:v for k,v in clean(x).items() if k not in ('package','path')}=={k:v for k,v in clean(y).items() if k not in ('package','path')}:continue
            row={'form':f,'logical_file':n,'A':clean(x) if x else None,'other':clean(y) if y else None}
            if x and y and not x['link'] and not y['link']:
                px,py=Path(x['file']),Path(y['file'])
                with px.open('rb') as xa,py.open('rb') as ya:elf=xa.read(4)==ya.read(4)==b'\x7fELF'
                if elf:row['sections']=sections(px,py)
                elif n.endswith(('.rlib','.a')):row['class']='archive/metadata: member-level causal attribution remains unproven'
                else:row['class']='non-ELF payload or pathname/content metadata'
            else:row['class']='file added/removed or link/mode change'
            differences.append(row)
    (out/'size-differences.json').write_text(json.dumps(differences,indent=2)+'\n')
    panic_rows={}
    for f,p in panics.items():
        matches=re.findall(r'(library/std/src/io/stdio\.rs):(\d+):(\d+)',p.read_text())
        if len(matches)!=1:raise RuntimeError('expected one stdio panic location for '+f)
        name,line,col=matches[0];hr=source('A',name);mr=source(f,name)
        resolved=asdict(locate(hr,mr,name,int(line),int(col),native=True))
        if b'failed printing to' not in hr.splitlines()[resolved['line']-1]:raise RuntimeError('resolver did not find authored std print panic')
        panic_rows[f]={'reported_path':name,'reported_line':int(line),'reported_column':int(col),'authored':resolved}
    (out/'panic-resolution.json').write_text(json.dumps(panic_rows,indent=2)+'\n')
    binaries={}
    for name in ('hello','regex-subject'):
        byform={}
        for r in results.glob('*/receipt.json'):
            s=json.loads(r.read_text())['step']
            p=r.parent/'result'/name
            if p.is_file():byform.setdefault(s['form'],[]).append(digest(p))
        if set(byform)!=set('ABC'):raise RuntimeError('missing program bytes: '+name)
        binaries[name]={'sha256':byform,'all_same':len(set(h for v in byform.values() for h in v))==1}
    (out/'program-bytes.json').write_text(json.dumps(binaries,indent=2)+'\n')
    (out/'step.json').write_text('{"complete":true}\n')
    shutil.rmtree('/work/unpacked')


if __name__=='__main__':main()
