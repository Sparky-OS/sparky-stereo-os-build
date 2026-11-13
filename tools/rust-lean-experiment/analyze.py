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
import itertools
import tempfile
import zlib
from elftools.elf.elffile import ELFFile
from rust_location import locate


def digest(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()


def logical(s):return re.sub(r'(?<=[./-])[0-9a-f]{16}(?=[./-]|$)','HASH',s)


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


def differing(a,b):
    return sum(c!=d for c,d in zip(a,b))+abs(len(a)-len(b))


def file_differences(a,b):
    count=0
    with a.open('rb') as fa,b.open('rb') as fb:
        while True:
            x,y=fa.read(1<<20),fb.read(1<<20)
            if not x and not y:return count
            if x!=y:count+=differing(x,y)


def section_chunks(section):
    if section is None or section['sh_type']=='SHT_NOBITS':return
    stream=section.stream;offset=section['sh_offset'];remaining=section['sh_size']
    decoder=None
    if section.compressed:
        size=section.structs.Elf_Chdr.sizeof();stream.seek(offset)
        header=section.structs.Elf_Chdr.parse(stream.read(size))
        if header['ch_type']!='ELFCOMPRESS_ZLIB':raise RuntimeError('unqualified ELF compression '+str(header['ch_type']))
        offset+=size;remaining-=size;decoder=zlib.decompressobj()
    stream.seek(offset);pending=b'';total=0
    while remaining:
        block=stream.read(min(1<<20,remaining))
        if not block:raise RuntimeError('truncated ELF section')
        remaining-=len(block)
        while block:
            data=decoder.decompress(block,1<<20) if decoder else block
            block=decoder.unconsumed_tail if decoder else b''
            pending+=data;total+=len(data)
            while len(pending)>=1<<20:
                yield pending[:1<<20];pending=pending[1<<20:]
    if decoder:
        while True:
            data=decoder.decompress(b'',1<<20)
            if not data:break
            total+=len(data);pending+=data
            while len(pending)>=1<<20:yield pending[:1<<20];pending=pending[1<<20:]
        if not decoder.eof:raise RuntimeError('truncated compressed ELF data')
    if total!=section.data_size:raise RuntimeError('ELF logical section length mismatch')
    if pending:yield pending


def sections(a,b):
    with a.open('rb') as fa,b.open('rb') as fb:
        aa=ELFFile(fa);bb=ELFFile(fb)
        sa={s.name:s for s in aa.iter_sections()};sb={s.name:s for s in bb.iter_sections()}
        rows=[]
        for n in sorted(sa.keys()|sb.keys()):
            x,y=sa.get(n),sb.get(n);changed=0;hx=hashlib.sha256();hy=hashlib.sha256()
            for dx,dy in itertools.zip_longest(section_chunks(x),section_chunks(y),fillvalue=b''):
                hx.update(dx);hy.update(dy)
                if dx!=dy:changed+=differing(dx,dy)
            size=lambda s:int(s['sh_size']) if s is not None else 0
            logical_size=lambda s:int(s.data_size) if s is not None else 0
            if not changed and size(x)==size(y) and logical_size(x)==logical_size(y):continue
            rows.append({'section':n,'A_stored_bytes':0 if x is not None and x['sh_type']=='SHT_NOBITS' else size(x),'other_stored_bytes':0 if y is not None and y['sh_type']=='SHT_NOBITS' else size(y),
                         'A_logical_bytes':logical_size(x),'other_logical_bytes':logical_size(y),
                         'different_bytes_at_logical_section_offsets':changed,
                         'A_logical_sha256':hx.hexdigest(),'other_logical_sha256':hy.hexdigest(),'class':classify(n)})
        return {'file_offset_different_bytes':file_differences(a,b),'sections':rows,
                'interpretation':'Logical section content is streamed, including zlib-compressed debug records. File-offset differences also include layout shifts; these coordinate counts must not be added. Panic locations are established by the runtime resolver; remaining causal contributions are explicit residuals.'}


def ar_members(path):
    rows={};strings=b''
    with path.open('rb') as f:
        if f.read(8)!=b'!<arch>\n':raise RuntimeError('unsupported archive format: '+str(path))
        while True:
            header=f.read(60)
            if not header:break
            if len(header)!=60 or header[58:]!=b'`\n':raise RuntimeError('invalid ar header')
            size=int(header[48:58]);start=f.tell();offset=start;length=size
            raw=header[:16].decode('ascii').strip()
            if raw=='//':strings=f.read(size);name='ARCHIVE_LONG_NAMES'
            elif raw in ('/','/SYM64/'):name='ARCHIVE_SYMBOL_INDEX'
            elif raw.startswith('#1/'):
                n=int(raw[3:]);name=f.read(n).rstrip(b'\0').decode('utf-8');offset+=n;length-=n
            elif raw.startswith('/'):
                i=int(raw[1:]);end=strings.find(b'/\n',i)
                if end<0:raise RuntimeError('invalid GNU ar string table')
                name=strings[i:end].decode('utf-8')
            else:name=raw.removesuffix('/')
            key=logical(name)
            if key in rows:raise RuntimeError('archive member identity collision: '+key)
            f.seek(offset);h=hashlib.sha256();remaining=length;magic=f.read(min(4,remaining));h.update(magic);remaining-=len(magic)
            while remaining:
                block=f.read(min(1<<20,remaining))
                if not block:raise RuntimeError('truncated archive member')
                h.update(block);remaining-=len(block)
            rows[key]={'name':name,'offset':offset,'bytes':length,'sha256':h.hexdigest(),'ELF':magic==b'\x7fELF','format':'ELF' if magic==b'\x7fELF' else 'WebAssembly' if magic==b'\0asm' else 'LLVM bitcode' if magic in (b'BC\xc0\xde',b'\xde\xc0\x17\x0b') else 'metadata/data'}
            f.seek(start+size+(size%2))
    return rows


def archive_differences(a,b,workdir=Path('/work')):
    left,right=ar_members(a),ar_members(b);rows=[]
    with tempfile.TemporaryDirectory(prefix='rl541-ar-',dir=workdir) as work:
        for key in sorted(left.keys()|right.keys()):
            x,y=left.get(key),right.get(key)
            if x and y and x['sha256']==y['sha256'] and x['bytes']==y['bytes']:continue
            row={'member':key,'A':x,'other':y}
            if x and y:
                paths=[]
                for source,info,name in ((a,x,'A'),(b,y,'B')):
                    target=Path(work)/name
                    with source.open('rb') as f,target.open('wb') as out:
                        f.seek(info['offset']);remaining=info['bytes']
                        while remaining:
                            block=f.read(min(1<<20,remaining))
                            if not block:raise RuntimeError('truncated archive member copy')
                            out.write(block);remaining-=len(block)
                    paths.append(target)
                row['file_offset_different_bytes']=file_differences(*paths)
                if x['ELF'] and y['ELF']:row['ELF']=sections(*paths)
                elif key.endswith('.rmeta') or key.startswith('lib.rmeta'):row['class']='Rust metadata: crate identities, spans and documentation; exact subfield attribution remains open'
                elif key.startswith('ARCHIVE_'):row['class']='archive index, names and layout metadata'
                else:row['class']='non-ELF object/bitcode/data; exact causal attribution remains open'
                for p in paths:p.unlink()
            else:row['class']='archive member added or removed'
            rows.append(row)
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
    identifiers={}
    for key,row in rows.items():
        p=Path(row['file'])
        if row['link'] or '/.build-id/' in key:continue
        with p.open('rb') as f:
            if f.read(4)!=b'\x7fELF':continue
            f.seek(0);elf=ELFFile(f)
            note=elf.get_section_by_name('.note.gnu.build-id')
            if note is not None:
                for n in note.iter_notes():
                    if n['n_type']=='NT_GNU_BUILD_ID':identifiers[n['n_desc']]=key
    remapped={}
    for key,row in rows.items():
        match=re.search(r'/\.build-id/([0-9a-f]{2})/([0-9a-f]+)\.debug$',key)
        if match:
            parent=identifiers.get(''.join(match.groups()))
            if parent:key='DEBUG-FOR/'+parent
        if key in remapped:raise RuntimeError('debug file correspondence collision: '+key)
        remapped[key]=row
    return remapped


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
                if elf:row['ELF']=sections(px,py)
                elif n.endswith(('.rlib','.a')):
                    row['class']='archive members: Rust metadata, object sections and archive indexes'
                    row['members']=archive_differences(px,py)
                elif n.endswith('.rmeta'):row['class']='Rust metadata: crate identities, spans and documentation; exact subfield attribution remains open'
                elif n.endswith(('.html','.js','.css')):row['class']='generated documentation, source views, indexes and source-line anchors'
                else:row['class']='non-ELF payload or pathname/content metadata'
                if not elf:row['file_offset_different_bytes']=file_differences(px,py)
            else:row['class']='file added/removed or link/mode change'
            differences.append(row)
    (out/'size-differences.json').write_text(json.dumps(differences,indent=2)+'\n')
    panic_rows={}
    for f,p in panics.items():
        matches=re.findall(r'(library/std/src/io/stdio\.rs):(\d+):(\d+)',p.read_text())
        if len(matches)!=1:raise RuntimeError('expected one stdio panic location for '+f)
        name,line,col=matches[0];hr=source('A',name);mr=source(f,name)
        resolved=asdict(locate(hr,mr,name,int(line),int(col)))
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
